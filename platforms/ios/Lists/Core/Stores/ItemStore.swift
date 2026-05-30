import Foundation
import Observation

/// Main-actor coordinator over `FileStore`. Owns the in-memory snapshot of
/// lists + items the UI binds to.
@MainActor
@Observable
public final class ItemStore {
    public private(set) var lists: [ItemList] = []
    public private(set) var items: [Item] = [] {
        didSet { itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }) }
    }
    /// PERF-1: id→item index kept in sync with `items`, so per-cell lookups in
    /// the collection-view bridges are O(1) instead of an O(items) linear scan
    /// on every row reconfigure (which fires for every row on every apply).
    public private(set) var itemsById: [UUID: Item] = [:]

    /// O(1) item lookup by id. Prefer over `items.first(where: { $0.id == id })`.
    public func item(_ id: UUID) -> Item? { itemsById[id] }

    public private(set) var isLoaded: Bool = false
    /// Original paths of files that failed to load and were quarantined on the
    /// last `bootstrap` (DI-1). Drives the "some notes couldn't be opened"
    /// banner; empty on a clean load.
    public private(set) var loadIssues: [String] = []
    /// CONC-4: guards bootstrap against a re-entrant double `.task` fire seeding
    /// sample data twice. Set synchronously before the first await.
    private var isBootstrapping = false

    private let store: FileStore
    private let scheduler: NotificationScheduler

    public init(store: FileStore, scheduler: NotificationScheduler = .shared) {
        self.store = store
        self.scheduler = scheduler
    }

    /// First-time bootstrap: ensure the Lists root exists, load whatever is
    /// already on disk, and (if empty) seed sample data.
    public func bootstrap() async throws {
        // CONC-4: a second (re-entrant/concurrent) bootstrap on the same store
        // must not run — otherwise both could observe an empty disk and seed.
        guard !isLoaded && !isBootstrapping else { return }
        isBootstrapping = true
        // Always finish "loading", even on a partial failure: showing an empty
        // sidebar + a banner beats hanging forever on "Loading…" (DI-1).
        defer { self.isLoaded = true; self.isBootstrapping = false }
        try await store.ensureRoot()
        let loaded = try await store.loadAll()
        self.loadIssues = loaded.quarantined.map(\.originalPath)

        // Only seed a genuinely-empty library. A quarantine-only load is NOT
        // empty — re-seeding there would write sample data on top of the user's
        // (recoverable) files.
        if loaded.lists.isEmpty && loaded.quarantined.isEmpty {
            let inbox = ItemList.makeInbox()
            let extraLists = SampleData.seedLists()
            let allLists = [inbox] + extraLists
            for list in allLists {
                try await store.writeList(list)
            }
            let samples = SampleData.seedItems(inboxId: inbox.id)
            for sample in samples {
                try await store.writeItem(sample)
            }
            self.lists = allLists
            self.items = samples
        } else {
            self.lists = loaded.lists.map(\.list)
            self.items = loaded.lists.flatMap(\.items)
        }
        try await purgeExpiredTombstones()
        for list in self.lists where list.deletedAt == nil {
            try? await migrateLegacySectionsIfNeeded(listId: list.id)
        }
    }

    // MARK: - Soft-deleted accessors

    public var deletedItems: [Item] {
        items.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    public var deletedLists: [ItemList] {
        lists.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// Best target for a "new item" capture: the active Inbox if it exists,
    /// otherwise the first non-deleted list by position. Returns nil when
    /// every list has been deleted — the UI should disable item creation in
    /// that case until the user adds a list back.
    public var defaultCaptureListId: String? {
        if let inbox = lists.first(where: { $0.id == ItemList.inboxId && $0.deletedAt == nil }) {
            return inbox.id
        }
        return lists
            .filter { $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
            .first?.id
    }

    public func toggleDone(_ id: UUID) async throws {
        guard var item = items.first(where: { $0.id == id }) else { return }
        let wasDone = item.done
        item.done.toggle()
        item.completedAt = item.done ? .now : nil
        item.modifiedAt = .now
        // CONC-1: apply the in-memory change before persisting, so a concurrent
        // mutation on this item can't resume to find memory and disk disagreeing.
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
        try await store.writeItem(item)
        if item.done {
            await scheduler.cancel(item.id)
            // TASK-1 / REM-1: on the completing transition, spawn the next
            // occurrence of a recurring task. The new dated item flows through
            // add(), which schedules its reminder — that is the REM-1 fix
            // (each occurrence is a discrete dated item, so repeats:false is
            // correct). Tasks only: habits track via completionLog; notes don't
            // complete. The `!wasDone` guard avoids a double-spawn on a rapid
            // double-toggle, and a task with no `due` has no anchor to advance.
            if !wasDone,
               item.type == .task,
               let rrule = item.recurrence?.rrule,
               let base = item.due,
               let nextDue = RecurrenceEngine.nextOccurrence(after: base, rrule: rrule) {
                var next = item
                next.id = UUID()
                next.done = false
                next.completedAt = nil
                next.due = nextDue
                next.createdAt = .now
                next.modifiedAt = .now
                try await add(next)
            }
        } else {
            await scheduler.schedule(item)
        }
    }

    /// Apply a change to a habit, keeping memory and disk consistent (CONC-1:
    /// in-memory first, then persist). No-op for non-habit items. Habit history
    /// edits don't touch reminders, so this never reschedules notifications.
    private func mutateHabit(_ id: UUID, _ change: (inout Item) -> Void) async throws {
        guard var item = items.first(where: { $0.id == id }), item.type == .habit else { return }
        change(&item)
        item.modifiedAt = .now
        if let idx = items.firstIndex(where: { $0.id == id }) {  // CONC-1: memory before disk
            items[idx] = item
        }
        try await store.writeItem(item)
    }

    /// Increment a habit's count for the current cycle (capped at goalPerCycle).
    /// Appends one timestamped completion event. No-op when already at goal.
    public func incrementHabit(_ id: UUID, now: Date = .now) async throws {
        guard let item = items.first(where: { $0.id == id }), item.type == .habit else { return }
        let key = HabitCycle.key(for: item.frequency ?? .daily, on: now)
        guard (item.completionLog[key] ?? 0) < item.goalPerCycle else { return }
        try await addCompletion(id, at: now)
    }

    /// Log a completion at an arbitrary instant (the Log's "add entry" / +1).
    public func addCompletion(_ id: UUID, at date: Date = .now) async throws {
        try await mutateHabit(id) { $0.completions.append(HabitCompletion(at: date)) }
    }

    /// Log many completions at once — one event per supplied date — in a single
    /// write (the Add Completion sheet's "Date Range" backfill). No-op when empty.
    public func addCompletions(_ id: UUID, on dates: [Date]) async throws {
        guard !dates.isEmpty else { return }
        try await mutateHabit(id) { item in
            item.completions.append(contentsOf: dates.map { HabitCompletion(at: $0) })
        }
    }

    /// Delete one logged completion (swipe-to-delete in the Log).
    public func deleteCompletion(_ id: UUID, completionId: UUID) async throws {
        try await mutateHabit(id) { $0.completions.removeAll { $0.id == completionId } }
    }

    /// Retime / redate one logged completion (tap-to-edit in the Log). Because
    /// `at` is absolute, this handles both "edit the time" and "move to another day".
    public func updateCompletion(_ id: UUID, completionId: UUID, to date: Date) async throws {
        try await mutateHabit(id) { item in
            if let idx = item.completions.firstIndex(where: { $0.id == completionId }) {
                item.completions[idx].at = date
            }
        }
    }

    /// Remove the most recent completion in the cycle containing `cycleOf` (the −1
    /// correction on the progress ring).
    public func removeLatestCompletion(in cycleOf: Date, for id: UUID) async throws {
        guard let item = items.first(where: { $0.id == id }), item.type == .habit else { return }
        let freq = item.frequency ?? .daily
        let key = HabitCycle.key(for: freq, on: cycleOf)
        let latest = item.completions
            .filter { HabitCycle.key(for: freq, on: $0.at) == key }
            .max(by: { $0.at < $1.at })
        guard let latest else { return }
        try await deleteCompletion(id, completionId: latest.id)
    }

    /// Set a habit's count for the cycle containing `date` by adding or removing
    /// events in that cycle (used by heatmap-day editing). Clamped to 0…goal.
    public func setHabitCount(_ id: UUID, count: Int, on date: Date) async throws {
        guard let snapshot = items.first(where: { $0.id == id }), snapshot.type == .habit else { return }
        let freq = snapshot.frequency ?? .daily
        let key = HabitCycle.key(for: freq, on: date)
        let target = max(0, min(count, snapshot.goalPerCycle))
        let inCycle = snapshot.completions.filter { HabitCycle.key(for: freq, on: $0.at) == key }
        if target == inCycle.count { return }
        try await mutateHabit(id) { item in
            if target < inCycle.count {
                let drop = Set(inCycle.sorted { $0.at > $1.at }.prefix(inCycle.count - target).map(\.id))
                item.completions.removeAll { drop.contains($0.id) }
            } else {
                for i in 0..<(target - inCycle.count) {
                    item.completions.append(HabitCompletion(at: date.addingTimeInterval(TimeInterval(i))))
                }
            }
        }
    }

    public func add(_ item: Item) async throws {
        var item = item
        item.modifiedAt = .now
        try await store.writeItem(item)
        items.append(item)
        await scheduler.schedule(item)
    }

    /// Create a new empty-title item for inline editing, appended at the END
    /// of its target group (top-level rows of `section`). `add()` defaults
    /// `sortIndex` to 0 and manual sort is ascending, so a naive new item would
    /// sort to the TOP — this computes `max(sortIndex)+1` so it lands at the
    /// bottom, Apple Reminders-style. Returns the new id so the caller can
    /// focus its inline editor. In-memory first; disk write + scheduling are
    /// fire-and-forget to keep the tap snappy (mirrors `applyUpdateSync`).
    @discardableResult
    public func addInlineItem(type: Item.ItemType, listId: String, section: String?) -> UUID {
        let siblings = items.filter {
            $0.listId == listId && $0.section == section && $0.parentId == nil && $0.deletedAt == nil
        }
        let nextSort = (siblings.map(\.sortIndex).max() ?? -1) + 1
        var item = Item(type: type, title: "", listId: listId, section: section, sortIndex: nextSort)
        if type == .habit {
            item.frequency = .daily
            item.goalPerCycle = 1
        }
        item.modifiedAt = .now
        items.append(item)
        let snapshot = item
        Task {
            try? await store.writeItem(snapshot)
            await scheduler.schedule(snapshot)
        }
        return item.id
    }

    /// Drag-to-reorder writeback: takes the flat user-visible sequence of
    /// item ids after a drag and renumbers `sortIndex` per parent group
    /// (top-level items sit in one group; each parent's direct children sit
    /// in their own). Items not in `flatOrderedIds` are left untouched. Only
    /// items whose new index actually differs are written.
    public func reorderItems(in listId: String, flatOrderedIds: [UUID]) async throws {
        var perGroupCounter: [UUID?: Int] = [:]
        for id in flatOrderedIds {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let next = perGroupCounter[item.parentId, default: 0]
            perGroupCounter[item.parentId] = next + 1
            if item.sortIndex == next { continue }
            var copy = item
            copy.sortIndex = next
            copy.modifiedAt = .now
            try await store.writeItem(copy)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = copy
            }
        }
    }

    /// Sync variant of `reorderItems` — updates the in-memory array
    /// immediately and persists to disk via a fire-and-forget Task. Use from
    /// UIKit drag/drop coordinators where the data source must reflect the
    /// new state *before* `UICollectionViewDropCoordinator.drop(_:toItemAt:)`
    /// animates the preview, otherwise the animation lands on stale cells
    /// and the move visually snaps back.
    public func applyReorderItemsSync(in listId: String, flatOrderedIds: [UUID]) {
        var changes: [Item] = []
        var perGroupCounter: [UUID?: Int] = [:]
        for id in flatOrderedIds {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let next = perGroupCounter[item.parentId, default: 0]
            perGroupCounter[item.parentId] = next + 1
            if item.sortIndex == next { continue }
            var copy = item
            copy.sortIndex = next
            copy.modifiedAt = .now
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = copy
            }
            changes.append(copy)
        }
        Task {
            for copy in changes {
                try? await store.writeItem(copy)
            }
        }
    }

    public func update(_ item: Item) async throws {
        var updated = item
        updated.modifiedAt = .now
        // DI-2: if the item changed lists, delete the stale file in the old
        // folder. The in-memory copy is the source of truth for the old path.
        let oldListId = items.first(where: { $0.id == item.id })?.listId
        // CONC-1: apply the in-memory change before persisting.
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.append(updated)
        }
        if let oldListId, oldListId != updated.listId {
            try await store.moveItem(updated, fromListId: oldListId)
        } else {
            try await store.writeItem(updated)
        }
        await scheduler.schedule(updated)
    }

    /// Sync variant of `update(_:)` — same rationale as
    /// `applyReorderItemsSync`. Disk write and notification scheduling are
    /// both fire-and-forget.
    public func applyUpdateSync(_ item: Item) {
        var updated = item
        updated.modifiedAt = .now
        // DI-2: capture the old list id *before* the in-memory assignment, so a
        // list change deletes the stale file on the detached write.
        let oldListId = items.first(where: { $0.id == item.id })?.listId
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.append(updated)
        }
        Task {
            if let oldListId, oldListId != updated.listId {
                try? await store.moveItem(updated, fromListId: oldListId)
            } else {
                try? await store.writeItem(updated)
            }
            await scheduler.schedule(updated)
        }
    }

    /// Remove `tag` (case-insensitive) from every non-deleted item that
    /// carries it. The items themselves are kept; only the tag is stripped.
    public func removeTag(_ tag: String) async throws {
        let lower = tag.lowercased()
        let affected = items.filter { item in
            item.deletedAt == nil
            && item.tags.contains { $0.lowercased() == lower }
        }
        for stale in affected {
            // CONC-2: re-fetch the current value inside the loop so an edit to
            // this item made during an earlier iteration's await isn't lost by
            // writing the pre-loop snapshot.
            guard var copy = items.first(where: { $0.id == stale.id }) else { continue }
            copy.tags.removeAll { $0.lowercased() == lower }
            try await update(copy)
        }
    }

    /// Rename `oldTag` → `newTag` across every non-deleted item. If an
    /// item already carries both, the duplicate is merged out. No-op when
    /// `newTag` sanitizes to nil or matches `oldTag` case-insensitively.
    public func renameTag(from oldTag: String, to newTag: String) async throws {
        guard let cleanNew = Tag.sanitize(newTag),
              cleanNew.caseInsensitiveCompare(oldTag) != .orderedSame else { return }
        let lowerOld = oldTag.lowercased()
        let lowerNew = cleanNew.lowercased()
        let affected = items.filter { item in
            item.deletedAt == nil
            && item.tags.contains { $0.lowercased() == lowerOld }
        }
        for stale in affected {
            // CONC-2: re-fetch the current value inside the loop (see removeTag).
            guard var copy = items.first(where: { $0.id == stale.id }) else { continue }
            var seen: Set<String> = []
            var rebuilt: [String] = []
            for t in copy.tags {
                let replaced = (t.lowercased() == lowerOld) ? cleanNew : t
                let key = replaced.lowercased()
                if key == lowerNew && seen.contains(lowerNew) { continue }
                if seen.insert(key).inserted {
                    rebuilt.append(replaced)
                }
            }
            copy.tags = rebuilt
            try await update(copy)
        }
    }

    // MARK: - Bulk operations (multi-select toolbar)
    //
    // Thin wrappers that loop the single-item APIs, re-fetching each item
    // inside the loop (CONC-2: an edit during an earlier iteration's await
    // must not be lost by writing a pre-loop snapshot).

    /// Set the flag on every selected item.
    public func bulkSetFlagged(_ ids: Set<UUID>, _ flagged: Bool) async throws {
        for id in ids {
            guard var copy = items.first(where: { $0.id == id }), copy.flagged != flagged else { continue }
            copy.flagged = flagged
            try await update(copy)
        }
    }

    /// Add a tag (case-insensitive, de-duplicated via `Tag.appending`) to every
    /// selected item. No-op when the tag sanitizes to nil.
    public func bulkAddTag(_ ids: Set<UUID>, tag: String) async throws {
        guard let clean = Tag.sanitize(tag) else { return }
        for id in ids {
            guard var copy = items.first(where: { $0.id == id }) else { continue }
            copy.tags = Tag.appending(clean, to: copy.tags)
            try await update(copy)
        }
    }

    /// Soft-delete every selected item.
    public func bulkSoftDelete(_ ids: Set<UUID>) async throws {
        for id in ids {
            try await softDelete(id)
        }
    }

    /// Move every selected item to another list. Clears each item's `section`
    /// — section ids are scoped to the source list and would orphan otherwise.
    public func bulkMove(_ ids: Set<UUID>, toListId newListId: String) async throws {
        for id in ids {
            guard var copy = items.first(where: { $0.id == id }), copy.listId != newListId else { continue }
            copy.listId = newListId
            copy.section = nil
            try await update(copy)
        }
    }

    /// Assign every selected item to `section` (nil = Others) within their list.
    public func bulkMove(_ ids: Set<UUID>, toSection section: String?) async throws {
        for id in ids {
            guard var copy = items.first(where: { $0.id == id }), copy.section != section else { continue }
            copy.section = section
            try await update(copy)
        }
    }

    public func delete(_ id: UUID) async throws {
        guard let item = items.first(where: { $0.id == id }) else { return }
        try await store.deleteItem(item)
        items.removeAll { $0.id == id }
        await scheduler.cancel(id)
    }

    /// Soft delete: marks an item with `deletedAt = now` and persists. Item
    /// stays on disk so it can be restored from Recently Deleted within 30 days.
    public func softDelete(_ id: UUID) async throws {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.deletedAt = .now
        item.modifiedAt = .now
        if let idx = items.firstIndex(where: { $0.id == id }) {  // CONC-1: memory before disk
            items[idx] = item
        }
        try await store.writeItem(item)
        await scheduler.cancel(id)
    }

    /// Restore: clears `deletedAt`.
    public func restore(_ id: UUID) async throws {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.deletedAt = nil
        item.modifiedAt = .now
        if let idx = items.firstIndex(where: { $0.id == id }) {  // CONC-1: memory before disk
            items[idx] = item
        }
        try await store.writeItem(item)
        await scheduler.schedule(item)
    }

    // MARK: - Lists

    public func addList(_ list: ItemList) async throws {
        var list = list
        list.modifiedAt = .now
        try await store.writeList(list)
        lists.append(list)
    }

    public func updateList(_ list: ItemList) async throws {
        var updated = list
        updated.modifiedAt = .now
        try await store.writeList(updated)
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = updated
        } else {
            lists.append(updated)
        }
    }

    /// Hard delete: removes the list folder + all items inside.
    public func deleteList(_ id: String) async throws {
        guard let list = lists.first(where: { $0.id == id }) else { return }
        try await store.deleteList(list)
        lists.removeAll { $0.id == id }
        items.removeAll { $0.listId == id }
    }

    /// Soft delete a list: stays on disk, hidden from active views, can be
    /// restored from Recently Deleted. Cascades to descendants — every nested
    /// sub-list also gets `deletedAt = now` so the entire subtree disappears
    /// together and shows up in Recently Deleted as separate restorable rows.
    public func softDeleteList(_ id: String) async throws {
        let now = Date()
        let ids = [id] + descendantIds(of: id)
        for targetId in ids {
            guard var list = lists.first(where: { $0.id == targetId }) else { continue }
            list.deletedAt = now
            list.modifiedAt = now
            list.lamport += 1
            try await store.writeList(list)
            if let idx = lists.firstIndex(where: { $0.id == targetId }) {
                lists[idx] = list
            }
        }
    }

    /// Restore: clears `deletedAt` and detaches the list from any
    /// still-deleted parent (it returns to the sidebar root). Items inside
    /// the list are unaffected — they were never tombstoned by the cascade.
    public func restoreList(_ id: String) async throws {
        guard var list = lists.first(where: { $0.id == id }) else { return }
        list.deletedAt = nil
        list.modifiedAt = .now
        list.lamport += 1
        if let pid = list.parentId,
           let parent = lists.first(where: { $0.id == pid }),
           parent.deletedAt != nil {
            list.parentId = nil
        }
        try await store.writeList(list)
        if let idx = lists.firstIndex(where: { $0.id == id }) {
            lists[idx] = list
        }
    }

    /// Move a list under a new parent (or to root if `newParentId` is nil).
    /// Rejects cycles — the new parent must not be the list itself or one of
    /// its descendants. The on-disk folder is physically moved by
    /// `FileStore.writeList`.
    public func moveList(_ id: String, toParent newParentId: String?) async throws {
        guard var list = lists.first(where: { $0.id == id }) else { return }
        if let newParentId {
            if newParentId == id { return }
            let descendants = Set(descendantIds(of: id))
            if descendants.contains(newParentId) { return }
        }
        list.parentId = newParentId
        list.modifiedAt = .now
        list.lamport += 1
        try await store.writeList(list)
        if let idx = lists.firstIndex(where: { $0.id == id }) {
            lists[idx] = list
        }
    }

    /// Commit a sidebar list drag in one shot. Reparents `movedId` under
    /// `newParentId` (nil = root, same cycle guard as `moveList`), then
    /// renumbers every visible group's `position` densely from
    /// `flatOrderedIds` (the post-drag render order). Mutates the in-memory
    /// snapshot first — so the diffable data source reflects the new state
    /// *before* `UICollectionViewDropCoordinator.drop(_:toItemAt:)` animates,
    /// otherwise the move snaps back — then a single fire-and-forget write
    /// pass over only the lists that actually changed. The moved list is
    /// written first so `FileStore.writeList` relocates its folder (and
    /// refreshes descendant paths) before any descendant position write.
    /// Returns false (no mutation) if the move would create a cycle.
    @discardableResult
    public func applyListReorderSync(
        movedId: String,
        toParent newParentId: String?,
        flatOrderedIds: [String]
    ) -> Bool {
        // Cycle guard — mirror moveList.
        if let newParentId {
            if newParentId == movedId { return false }
            if Set(descendantIds(of: movedId)).contains(newParentId) { return false }
        }

        var dirty: Set<String> = []

        // 1. Reparent the moved list in memory.
        if let idx = lists.firstIndex(where: { $0.id == movedId }),
           lists[idx].parentId != newParentId {
            lists[idx].parentId = newParentId
            dirty.insert(movedId)
        }

        // 2. Renumber positions densely per parent group, in render order.
        //    Collapsed (non-visible) groups keep their existing positions —
        //    they aren't in `flatOrderedIds`, so their counters never run.
        var perGroup: [String?: Double] = [:]
        for id in flatOrderedIds {
            guard let idx = lists.firstIndex(where: { $0.id == id }) else { continue }
            let parent = lists[idx].parentId
            let next = (perGroup[parent] ?? 0) + 1
            perGroup[parent] = next
            if lists[idx].position != next {
                lists[idx].position = next
                dirty.insert(id)
            }
        }

        guard !dirty.isEmpty else { return true }

        // 3. Stamp + persist once each, moved list first.
        let now = Date()
        let ordered = (dirty.contains(movedId) ? [movedId] : [])
            + dirty.subtracting([movedId]).sorted()
        var changes: [ItemList] = []
        for id in ordered {
            guard let idx = lists.firstIndex(where: { $0.id == id }) else { continue }
            lists[idx].modifiedAt = now
            lists[idx].lamport += 1
            changes.append(lists[idx])
        }
        Task {
            for list in changes {
                try? await store.writeList(list)
            }
        }
        return true
    }

    // MARK: - Bulk list operations (multi-select toolbar)
    //
    // Thin wrappers that loop the single-list APIs (mirror the item bulk ops
    // above). Each re-fetches via the looped method so an edit during an
    // earlier iteration's await isn't lost (CONC-2).

    /// Soft-delete every selected list. `softDeleteList` already cascades to
    /// descendants, so a selection holding both a parent and its child is
    /// safe — the child's second pass just re-tombstones harmlessly.
    public func bulkSoftDeleteLists(_ ids: Set<String>) async throws {
        for id in ids {
            try await softDeleteList(id)
        }
    }

    /// Move every selected list under `newParentId` (nil = root). `moveList`
    /// cycle-guards each id, silently skipping a move that would nest a list
    /// under itself or one of its descendants.
    public func bulkMoveLists(_ ids: Set<String>, toParent newParentId: String?) async throws {
        for id in ids {
            try await moveList(id, toParent: newParentId)
        }
    }

    // MARK: - Sections

    /// Append a new section to the list. Returns the created `ListSection` so
    /// callers can highlight it after creation.
    @discardableResult
    public func addSection(in listId: String, name: String) async throws -> ListSection? {
        guard var list = lists.first(where: { $0.id == listId }) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextPos = (list.sections.map(\.position).max() ?? 0) + 1000
        let section = ListSection(name: trimmed, position: nextPos)
        list.sections.append(section)
        try await updateList(list)
        return section
    }

    /// Promote the synthetic "Others" bucket into a real named section: create
    /// a new `ListSection` with the given name and reassign every loose item
    /// (`section == nil`) in the list to its id. Any future loose items will
    /// once again surface under a fresh "Others" bucket.
    public func promoteOthersToSection(in listId: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var list = lists.first(where: { $0.id == listId }) else { return }
        let looseIds = items
            .filter { $0.listId == listId && $0.section == nil && $0.deletedAt == nil }
            .map(\.id)
        guard !looseIds.isEmpty else { return }
        let nextPos = (list.sections.map(\.position).max() ?? 0) + 1000
        let section = ListSection(name: trimmed, position: nextPos)
        list.sections.append(section)
        try await updateList(list)
        let sidStr = section.id.uuidString
        for id in looseIds {
            guard var it = items.first(where: { $0.id == id }) else { continue }
            it.section = sidStr
            try await update(it)
        }
    }

    /// Rename a section in-place. Items keep their `section` id reference, so
    /// no item rewrites are needed.
    public func renameSection(_ sectionId: UUID, in listId: String, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var list = lists.first(where: { $0.id == listId }),
              let idx = list.sections.firstIndex(where: { $0.id == sectionId }) else { return }
        if list.sections[idx].name == trimmed { return }
        list.sections[idx].name = trimmed
        try await updateList(list)
    }

    /// Apply a new ordering of section ids. Missing ids are dropped; unknown
    /// ids are ignored. `position` is renumbered densely so the on-disk order
    /// matches the new sequence.
    public func reorderSections(in listId: String, orderedIds: [UUID]) async throws {
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        let bySectionId = Dictionary(uniqueKeysWithValues: list.sections.map { ($0.id, $0) })
        var rebuilt: [ListSection] = []
        var pos: Double = 1000
        for id in orderedIds {
            guard var s = bySectionId[id] else { continue }
            s.position = pos
            rebuilt.append(s)
            pos += 1000
        }
        if rebuilt.count != list.sections.count { return }
        list.sections = rebuilt
        try await updateList(list)
    }

    /// Sync variant of `reorderSections` — same rationale as
    /// `applyReorderItemsSync`. Disk write is fire-and-forget.
    public func applyReorderSectionsSync(in listId: String, orderedIds: [UUID]) {
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        let bySectionId = Dictionary(uniqueKeysWithValues: list.sections.map { ($0.id, $0) })
        var rebuilt: [ListSection] = []
        var pos: Double = 1000
        for id in orderedIds {
            guard var s = bySectionId[id] else { continue }
            s.position = pos
            rebuilt.append(s)
            pos += 1000
        }
        if rebuilt.count != list.sections.count { return }
        list.sections = rebuilt
        list.modifiedAt = .now
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = list
        }
        let snapshot = list
        Task {
            try? await store.writeList(snapshot)
        }
    }

    /// Delete a section. When `cascadingItems` is true (the default — matches
    /// the Delete-List pattern), every item assigned to that section is soft-
    /// deleted alongside it. When false, items are detached (their `section`
    /// becomes `nil`) and live on as ungrouped items in the list.
    public func deleteSection(
        _ sectionId: UUID,
        in listId: String,
        cascadingItems: Bool = true
    ) async throws {
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        let sidStr = sectionId.uuidString
        let affectedIds = items
            .filter { $0.listId == listId && $0.section == sidStr && $0.deletedAt == nil }
            .map(\.id)

        if cascadingItems {
            for id in affectedIds {
                try await softDelete(id)
            }
        } else {
            for id in affectedIds {
                guard var it = items.first(where: { $0.id == id }) else { continue }
                it.section = nil
                try await update(it)
            }
        }

        list.sections.removeAll { $0.id == sectionId }
        try await updateList(list)
    }

    /// Atomic commit from the Edit Sections sheet. `kept` is the post-edit
    /// list of sections (renames + reorder applied); `deleted` is the ids that
    /// were removed. Items in deleted sections are soft-deleted alongside.
    public func commitSectionEdits(
        in listId: String,
        kept: [ListSection],
        deleted: [UUID]
    ) async throws {
        for sid in deleted {
            let sidStr = sid.uuidString
            let affected = items
                .filter { $0.listId == listId && $0.section == sidStr && $0.deletedAt == nil }
                .map(\.id)
            for id in affected {
                try await softDelete(id)
            }
        }
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        // Renumber position densely in the order provided.
        var pos: Double = 1000
        list.sections = kept.map { s in
            var copy = s
            copy.position = pos
            pos += 1000
            return copy
        }
        try await updateList(list)
    }

    /// One-shot migration for lists where items have a legacy free-form
    /// `Item.section` string (the pre-`ListSection` schema) but the list has
    /// no `sections` defined. Each unique legacy string becomes a
    /// `ListSection` (in first-appearance order), and the items are rewritten
    /// to reference the new section's UUID. Idempotent — no-op once a list
    /// has sections, or when no items carry a legacy string.
    public func migrateLegacySectionsIfNeeded(listId: String) async throws {
        guard var list = lists.first(where: { $0.id == listId }) else { return }
        guard list.sections.isEmpty else { return }
        let listItems = items.filter { $0.listId == listId && $0.deletedAt == nil }
        var orderedNames: [String] = []
        var seen: Set<String> = []
        for it in listItems {
            guard let s = it.section, !s.isEmpty else { continue }
            // A section already-migrated would be a UUID string; skip those.
            if UUID(uuidString: s) != nil { continue }
            if seen.insert(s).inserted { orderedNames.append(s) }
        }
        guard !orderedNames.isEmpty else { return }

        var sections: [ListSection] = []
        var nameToId: [String: UUID] = [:]
        var pos: Double = 1000
        for name in orderedNames {
            let section = ListSection(name: name, position: pos)
            sections.append(section)
            nameToId[name] = section.id
            pos += 1000
        }
        list.sections = sections
        try await updateList(list)

        for it in listItems {
            guard let s = it.section, let newId = nameToId[s] else { continue }
            var copy = it
            copy.section = newId.uuidString
            try await update(copy)
        }
    }

    // MARK: - Hierarchy helpers

    /// Direct children of `parentId` (non-deleted), sorted by position.
    public func children(of parentId: String?) -> [ItemList] {
        lists
            .filter { $0.parentId == parentId && $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
    }

    /// All descendants of `id` (children, grandchildren, …) — non-deleted.
    /// Used by cascade delete and the cycle guard.
    public func descendantIds(of id: String) -> [String] {
        var out: [String] = []
        var stack: [String] = [id]
        while let next = stack.popLast() {
            for child in lists where child.parentId == next && child.deletedAt == nil {
                out.append(child.id)
                stack.append(child.id)
            }
        }
        return out
    }

    /// Auto-purge tombstones older than 30 days. Called from bootstrap.
    private func purgeExpiredTombstones() async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        for item in items where (item.deletedAt ?? .distantFuture) < cutoff {
            try? await store.deleteItem(item)
        }
        items.removeAll { ($0.deletedAt ?? .distantFuture) < cutoff }

        for list in lists where (list.deletedAt ?? .distantFuture) < cutoff {
            try? await store.deleteList(list)
            items.removeAll { $0.listId == list.id }
        }
        lists.removeAll { ($0.deletedAt ?? .distantFuture) < cutoff }
    }

    /// Return items matching a smart list, sorted oldest-due-first (overdue at top).
    /// `lingering` is a set of ids that should remain visible regardless of the
    /// smart-list filter — used by views to keep a just-completed item on screen
    /// for the linger window before it fades out. `showCompleted` extends the
    /// match to include done items that would otherwise be filtered out (no-op
    /// for the `.completed` smart list, which already shows done items).
    public func items(
        for query: SmartList,
        showCompleted: Bool = false,
        lingering: Set<UUID> = [],
        now: Date = .now
    ) -> [Item] {
        items
            .filter { item in
                if item.deletedAt != nil { return false }
                if lingering.contains(item.id) { return true }
                return query.matches(item, now: now, includeCompleted: showCompleted)
            }
            .sorted(by: Self.byDue)
    }

    private static func byDue(_ lhs: Item, _ rhs: Item) -> Bool {
        let l = lhs.due ?? .distantFuture
        let r = rhs.due ?? .distantFuture
        if l != r { return l < r }
        return lhs.title < rhs.title
    }
}
