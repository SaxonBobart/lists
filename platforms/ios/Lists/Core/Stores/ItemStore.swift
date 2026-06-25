import Foundation
import Observation
import os

/// Main-actor coordinator over `FileStore`. Owns the in-memory snapshot of
/// lists + items the UI binds to.
@MainActor
@Observable
public final class ItemStore {
    public private(set) var lists: [ItemList] = []
    public private(set) var items: [Item] = [] {
        didSet { itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }) }
    }
    /// Id-to-item index kept in sync with `items`, so per-cell lookups in the
    /// collection-view bridges are O(1) instead of an O(items) linear scan on
    /// every row reconfigure.
    public private(set) var itemsById: [UUID: Item] = [:]

    /// O(1) item lookup by id. Prefer over `items.first(where: { $0.id == id })`.
    public func item(_ id: UUID) -> Item? { itemsById[id] }

    public private(set) var isLoaded: Bool = false
    /// Original paths of files that failed to load and were quarantined on the
    /// last `bootstrap`. Drives the "some files couldn't be opened" banner;
    /// empty on a clean load.
    public private(set) var loadIssues: [String] = []
    /// Guards bootstrap against a re-entrant double `.task` fire seeding sample
    /// data twice. Set synchronously before the first await.
    private var isBootstrapping = false

    private let store: FileStore
    private let scheduler: NotificationScheduler

    public init(store: FileStore, scheduler: NotificationScheduler = .shared) {
        self.store = store
        self.scheduler = scheduler
    }

    // MARK: - Ordered persistence

    private static let log = Logger(
        subsystem: "io.github.saxonbobart.lists", category: "persistence")

    /// Every disk write is appended to one FIFO chain, so a deferred
    /// (fire-and-forget) write can never land after a newer write to the same
    /// file and silently revert it on the next launch. Awaited writes flow
    /// through the same chain, keeping ordering global across both kinds.
    private var writeChain: Task<Void, Never>?

    /// Append an ordered write and await its result.
    private func enqueueWrite<T: Sendable>(
        _ op: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let previous = writeChain
        let task = Task<T, Error> {
            await previous?.value
            return try await op()
        }
        writeChain = Task { _ = try? await task.value }
        return try await task.value
    }

    /// Append an ordered write without awaiting it (the sync UIKit-bridge
    /// paths, where the data source must mutate before the drop animation).
    /// Failures are logged — never silently swallowed.
    private func enqueueDetachedWrite(
        _ context: String,
        _ op: @escaping @Sendable () async throws -> Void
    ) {
        let previous = writeChain
        writeChain = Task {
            await previous?.value
            do {
                try await op()
            } catch {
                Self.log.error("""
                    Deferred write (\(context, privacy: .public)) failed: \
                    \(String(describing: error), privacy: .private)
                    """)
            }
        }
    }

    /// Await every disk write queued so far. Tests use this to assert
    /// on-disk state after the synchronous UI-bridge mutation paths whose
    /// writes are queued in the background.
    public func flushPendingWrites() async {
        await writeChain?.value
    }

    // Ordered wrappers around the FileStore verbs. All ItemStore persistence
    // goes through these so the FIFO guarantee covers every write.
    private func writeItemOrdered(_ item: Item) async throws {
        try await enqueueWrite { [store] in try await store.writeItem(item) }
    }
    private func writeListOrdered(_ list: ItemList) async throws {
        try await enqueueWrite { [store] in try await store.writeList(list) }
    }
    private func moveItemOrdered(_ item: Item, fromListId: String) async throws {
        try await enqueueWrite { [store] in try await store.moveItem(item, fromListId: fromListId) }
    }
    private func deleteItemOrdered(_ item: Item) async throws {
        try await enqueueWrite { [store] in try await store.deleteItem(item) }
    }
    private func deleteListOrdered(_ list: ItemList) async throws {
        try await enqueueWrite { [store] in try await store.deleteList(list) }
    }

    /// First-time bootstrap: ensure the Lists root exists, load whatever is
    /// already on disk, and (if empty) seed sample data.
    public func bootstrap() async throws {
        // A second bootstrap on the same store must not run; otherwise both
        // could observe an empty disk and seed.
        guard !isLoaded && !isBootstrapping else { return }
        isBootstrapping = true
        // Always finish "loading", even on a partial failure: showing an empty
        // sidebar + a banner beats hanging forever on "Loading…".
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
                try await writeListOrdered(list)
            }
            let samples = SampleData.seedItems(inboxId: inbox.id)
            for sample in samples {
                try await writeItemOrdered(sample)
            }
            self.lists = allLists
            self.items = samples
        } else {
            self.lists = loaded.lists.map(\.list)
            self.items = loaded.lists.flatMap(\.items)
        }
        try await purgeExpiredTombstones()
        await repairLoadedListHierarchy()
        for list in self.lists where list.deletedAt == nil {
            try? await migrateLegacySectionsIfNeeded(listId: list.id)
        }
        await repairLoadedItemHierarchy()
    }

    /// Re-read the on-disk library and replace the in-memory snapshot.
    ///
    /// Files are the source of truth; this rebuilds the app's live view of
    /// them without seeding sample data into an empty folder.
    public func reloadFromDisk() async throws {
        await flushPendingWrites()
        try await store.ensureRoot()

        let loaded = try await store.loadAll()
        self.loadIssues = loaded.quarantined.map(\.originalPath)
        self.lists = loaded.lists.map(\.list)
        self.items = loaded.lists.flatMap(\.items)
        self.isLoaded = true

        try await purgeExpiredTombstones()
        await repairLoadedListHierarchy()
        for list in self.lists where list.deletedAt == nil {
            try? await migrateLegacySectionsIfNeeded(listId: list.id)
        }
        await repairLoadedItemHierarchy()
    }

    /// Flush pending writes and package the app-private Lists folder for sharing.
    public func exportLibrary() async throws -> URL {
        await flushPendingWrites()
        try await store.ensureRoot()
        let root = await store.rootURL()
        return try await Task.detached(priority: .userInitiated) {
            try LibraryExporter.exportLibrary(at: root)
        }.value
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

    /// Count shown beside user lists. This follows the same product rule as
    /// list visibility: active items that are not complete and have not rolled
    /// off as past calendar events still need attention.
    public func openItemCount(
        in listId: String,
        now: Date = .now,
        itemTypePolicy: ItemTypePolicy = .allEnabled
    ) -> Int {
        items.filter { item in
            item.listId == listId
                && item.deletedAt == nil
                && item.isAvailable(in: itemTypePolicy)
                && !item.isComplete(at: now)
                && !item.isRolledOffPastEvent(now: now)
        }.count
    }

    public func toggleDone(_ id: UUID) async throws {
        guard var item = items.first(where: { $0.id == id }) else { return }
        // A non-completable event has no done state to toggle — when it
        // passes, it's simply past.
        if item.type == .event && !item.completable { return }
        let now = Date.now
        let wasDone = item.done
        item.done.toggle()
        item.completedAt = item.done ? now : nil
        item.modifiedAt = now
        // Apply the in-memory change before persisting, so a concurrent
        // mutation on this item can't resume to find memory and disk disagreeing.
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
        try await writeItemOrdered(item)
        guard item.done else {
            await scheduler.schedule(item)
            return
        }
        await scheduler.cancel(item.id)

        // On the completing transition, spawn the next occurrence of a
        // recurring task or completable event. The new dated item flows through
        // add(), which schedules its reminder. Each occurrence is a discrete
        // dated item, so a non-repeating notification is correct. Habits track
        // via completionLog; notes and non-completable events don't complete.
        // The `!wasDone` guard avoids a double-spawn on a rapid double-toggle,
        // and an item with no `due` has no anchor to advance.
        //
        // The successor is built from a re-fetched live copy. The awaits above
        // are suspension points, and a concurrent edit landing during them must
        // not be resurrected as stale title/body/tags in the new occurrence. If
        // the item was un-completed mid-flight, don't spawn.
        // Placement (parent/section/sortIndex) is inherited deliberately: a
        // recurring sub-task's next occurrence stays where the original lived.
        guard !wasDone,
              let live = self.item(id), live.done,
              live.type == .task || (live.type == .event && live.completable),
              let rrule = live.recurrence?.rrule,
              let base = live.due
        else { return }
        let calendar = RecurrenceEngine.calendar(forTimeZone: live.dueTimeZone)

        // Completing a long-overdue task must not spawn a successor that is
        // itself already in the past. It would get no reminder and the series
        // would quietly die. Step the rule forward (anchored to the original
        // due, so "every Monday 9am" stays on Mondays) until the next
        // occurrence is in the future, or the series ends at UNTIL.
        var nextDue = RecurrenceEngine.nextOccurrence(after: base, rrule: rrule, calendar: calendar)
        var hops = 0
        while let candidate = nextDue, candidate <= now, hops < 1000 {
            nextDue = RecurrenceEngine.nextOccurrence(after: candidate, rrule: rrule, calendar: calendar)
            hops += 1
        }
        guard let nextDue else { return }

        // Tick -> untick -> tick must not leave two copies of the same future
        // occurrence. If an open sibling with the same rule, list, title and
        // computed due already exists, this completion already has its
        // successor, so don't spawn another.
        let alreadySpawned = items.contains {
            $0.id != live.id && $0.deletedAt == nil && !$0.done
                && $0.type == live.type
                && $0.listId == live.listId
                && $0.title == live.title
                && $0.recurrence?.rrule == rrule
                && $0.due == nextDue
        }
        guard !alreadySpawned else { return }

        var next = live
        next.id = UUID()
        next.done = false
        next.completedAt = nil
        next.due = nextDue
        // A recurring event's span keeps its duration: end advances with due.
        next.end = live.end.map { nextDue.addingTimeInterval($0.timeIntervalSince(base)) }
        next.createdAt = now
        next.modifiedAt = now
        try await add(next)
    }

    /// Apply a change to a habit, keeping memory and disk consistent
    /// (in-memory first, then persist). No-op for non-habit items. Habit
    /// history edits don't touch reminders, so this never reschedules
    /// notifications.
    private func mutateHabit(_ id: UUID, _ change: (inout Item) -> Void) async throws {
        guard var item = items.first(where: { $0.id == id }), item.type == .habit else { return }
        change(&item)
        item.modifiedAt = .now
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
        try await writeItemOrdered(item)
    }

    /// Increment a habit's count for the current cycle (capped at goalPerCycle).
    /// Appends one timestamped completion event. No-op when already at goal.
    public func incrementHabit(_ id: UUID, now: Date = .now) async throws {
        guard let item = items.first(where: { $0.id == id }), item.type == .habit else { return }
        // Writers bucket on the same normalized cadence the readers
        // (completionLog / isComplete / stats) use.
        let key = HabitCycle.key(for: (item.frequency ?? .daily).normalizedForHabit, on: now)
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
        let freq = (item.frequency ?? .daily).normalizedForHabit
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
        let freq = (snapshot.frequency ?? .daily).normalizedForHabit
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
        var item = normalizedForStorage(item)
        item.modifiedAt = .now
        try await writeItemOrdered(item)
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
        var item = normalizedForStorage(
            Item(type: type, title: "", listId: listId, section: section, sortIndex: 0)
        )
        let siblings = items.filter {
            $0.listId == item.listId && $0.section == item.section && $0.parentId == nil && $0.deletedAt == nil
        }
        item.sortIndex = (siblings.map(\.sortIndex).max() ?? -1) + 1
        if type == .habit {
            item.frequency = .daily
            item.goalPerCycle = 1
        }
        item.modifiedAt = .now
        items.append(item)
        let snapshot = item
        enqueueDetachedWrite("inline-add \(snapshot.id)") { [store] in
            try await store.writeItem(snapshot)
        }
        Task { await scheduler.schedule(snapshot) }
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
            try await writeItemOrdered(copy)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = copy
            }
        }
    }

    /// Synchronous UI-bridge variant of `reorderItems` — updates the in-memory
    /// array immediately and persists to disk via a queued background write.
    /// Use from UIKit drag/drop coordinators where the data source must reflect
    /// the new state *before* `UICollectionViewDropCoordinator.drop(_:toItemAt:)`
    /// animates the preview, otherwise the animation lands on stale cells and
    /// the move visually snaps back.
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
        enqueueDetachedWrite("item reorder in \(listId)") { [store, changes] in
            for copy in changes {
                try await store.writeItem(copy)
            }
        }
    }

    public func update(_ item: Item) async throws {
        var updated = normalizedForStorage(item)
        updated.modifiedAt = .now
        // If the item changed lists, delete the stale file in the old folder.
        // The in-memory copy is the source of truth for the old path.
        let oldListId = items.first(where: { $0.id == item.id })?.listId
        // Apply the in-memory change before persisting.
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.append(updated)
        }
        if let oldListId, oldListId != updated.listId {
            try await moveItemOrdered(updated, fromListId: oldListId)
        } else {
            try await writeItemOrdered(updated)
        }
        await scheduler.schedule(updated)
    }

    /// Update an item and keep its hierarchy coherent when the edit moves it.
    /// Detail screens use this for their list and section controls so stored
    /// data matches the visible hierarchy.
    public func updateWithSubtreeCascades(_ item: Item) async throws {
        let previous = items.first(where: { $0.id == item.id })
        let normalized = normalizedForStorage(item)
        try await update(normalized)
        guard let previous else { return }
        if previous.listId != normalized.listId {
            try await moveDescendantsToList(parentId: normalized.id, listId: normalized.listId)
        }
        if previous.section != normalized.section {
            applySectionCascadeSync(toDescendantsOf: normalized.id, section: normalized.section)
        }
    }

    /// Synchronous UI-bridge variant of `update(_:)` — same rationale as
    /// `applyReorderItemsSync`. Disk write and notification scheduling are
    /// both queued in the background.
    public func applyUpdateSync(_ item: Item) {
        var updated = normalizedForStorage(item)
        updated.modifiedAt = .now
        // Capture the old list id before the in-memory assignment, so a list
        // change deletes the stale file on the detached write.
        let oldListId = items.first(where: { $0.id == item.id })?.listId
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.append(updated)
        }
        enqueueDetachedWrite("update \(updated.id)") { [store, updated] in
            if let oldListId, oldListId != updated.listId {
                try await store.moveItem(updated, fromListId: oldListId)
            } else {
                try await store.writeItem(updated)
            }
        }
        Task { await scheduler.schedule(updated) }
    }

    /// Synchronous UI-bridge variant of `updateWithSubtreeCascades(_:)` for
    /// live-apply UI.
    public func applyUpdateWithSubtreeCascadesSync(_ item: Item) {
        let previous = items.first(where: { $0.id == item.id })
        let normalized = normalizedForStorage(item)
        applyUpdateSync(normalized)
        guard let previous else { return }
        if previous.listId != normalized.listId {
            applyListCascadeSync(toDescendantsOf: normalized.id, listId: normalized.listId)
        }
        if previous.section != normalized.section {
            applySectionCascadeSync(toDescendantsOf: normalized.id, section: normalized.section)
        }
    }

    /// Stored hierarchy invariant:
    /// - a child must point at a live parent in the same list,
    /// - a child inherits its parent's section,
    /// - a top-level item can only keep a section id that belongs to its list.
    /// - a habit does not persist a markdown notes body.
    /// UI flows may edit list/section from different surfaces; normalizing here
    /// keeps those surfaces from inventing subtly different product rules.
    private func normalizedForStorage(_ item: Item) -> Item {
        var normalized = item

        if normalized.type == .habit {
            normalized.body = ""
            normalized.frequency = normalized.frequency?.normalizedForHabit ?? .daily
            normalized.goalPerCycle = max(1, normalized.goalPerCycle)
        }

        if normalized.type == .event {
            EventDefaults.normalize(&normalized)
        } else {
            normalized.end = nil
            normalized.completable = false
        }

        if let parentId = normalized.parentId {
            let invalidParent = parentId == normalized.id
                || itemDescendantIds(of: normalized.id).contains(parentId)
            if invalidParent {
                normalized.parentId = nil
            } else if let parent = self.item(parentId),
                      parent.deletedAt == nil,
                      parent.listId == normalized.listId {
                normalized.section = parent.section
            } else {
                normalized.parentId = nil
            }
        }

        guard normalized.parentId == nil,
              let section = normalized.section,
              !section.isEmpty,
              let list = lists.first(where: { $0.id == normalized.listId && $0.deletedAt == nil }) else {
            return normalized
        }

        if !list.sections.contains(where: { $0.id.uuidString == section }) {
            normalized.section = nil
        }
        return normalized
    }

    /// Apply the same hierarchy invariant to data loaded from disk. Write
    /// paths already normalize, but imported, hand-edited, or older files can
    /// still contain invisible children or stale section ids.
    private func repairLoadedItemHierarchy() async {
        var changedIds: Set<UUID> = []
        var deletedListDates: [String: Date] = [:]
        for list in lists {
            if let deletedAt = list.deletedAt {
                deletedListDates[list.id] = deletedAt
            }
        }
        for idx in items.indices where items[idx].deletedAt == nil {
            if let deletedAt = deletedListDates[items[idx].listId] {
                items[idx].deletedAt = deletedAt
                items[idx].modifiedAt = .now
                changedIds.insert(items[idx].id)
            }
        }

        var didChange = true
        var remainingPasses = max(items.count, 1)
        while didChange && remainingPasses > 0 {
            didChange = false
            remainingPasses -= 1
            for idx in items.indices where items[idx].deletedAt == nil {
                let normalized = normalizedForStorage(items[idx])
                guard normalized != items[idx] else { continue }
                items[idx] = normalized
                changedIds.insert(normalized.id)
                didChange = true
            }
        }

        for id in changedIds {
            guard let item = item(id) else { continue }
            try? await writeItemOrdered(item)
            if item.deletedAt != nil {
                await scheduler.cancel(item.id)
            }
        }
    }

    /// Apply list-parent invariants to data loaded from disk. Write paths guard
    /// these already, but hand-edited or older `.list.yml` files can still point
    /// a visible list at a missing/deleted parent or into a cycle, which strands
    /// it outside the sidebar tree.
    private func repairLoadedListHierarchy() async {
        let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let repairIndexes = lists.indices.filter { idx in
            guard let parentId = lists[idx].parentId else { return false }
            return ListHierarchy.invalidLoadedParent(parentId, for: lists[idx], in: byId)
        }

        var changedIds: [String] = []
        for idx in repairIndexes {
            lists[idx].parentId = nil
            lists[idx].modifiedAt = .now
            lists[idx].lamport += 1
            changedIds.append(lists[idx].id)
        }

        for id in changedIds {
            guard let list = lists.first(where: { $0.id == id }) else { continue }
            try? await writeListOrdered(list)
        }
    }

    /// Move or reparent one item using the app's hierarchy rules:
    /// - choosing a parent also inherits that parent's list and section,
    /// - choosing no parent inside the same list keeps the current section,
    /// - choosing no parent in another list clears the list-scoped section,
    /// - descendants follow the moved item's list/section so stored data matches
    ///   the visible tree.
    @discardableResult
    public func applyMoveSync(itemId: UUID, toListId listId: String, parentId: UUID?) -> Bool {
        guard lists.contains(where: { $0.id == listId && $0.deletedAt == nil }),
              var moving = item(itemId),
              moving.deletedAt == nil else {
            return false
        }

        let targetSection: String?
        if let parentId {
            guard let parent = item(parentId),
                  parent.deletedAt == nil,
                  parent.listId == listId,
                  parent.id != itemId,
                  !itemDescendantIds(of: itemId).contains(parent.id) else {
                return false
            }
            targetSection = parent.section
        } else if moving.listId != listId {
            targetSection = nil
        } else {
            targetSection = moving.section
        }

        let movedAcrossLists = moving.listId != listId
        let sectionChanged = moving.section != targetSection
        moving.listId = listId
        moving.parentId = parentId
        moving.section = targetSection

        applyUpdateSync(moving)
        if movedAcrossLists {
            applyListCascadeSync(toDescendantsOf: itemId, listId: listId)
        }
        if sectionChanged {
            applySectionCascadeSync(toDescendantsOf: itemId, section: targetSection)
        }
        return true
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
            // Re-fetch the current value inside the loop so an edit made during
            // an earlier iteration's await isn't lost by writing the pre-loop
            // snapshot.
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
            // Re-fetch the current value inside the loop (see removeTag).
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
    // inside the loop so an edit during an earlier iteration's await is not
    // lost by writing a pre-loop snapshot.

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

    /// Move selected item roots to another list. Descendants of a selected root
    /// move with that root; a selected child whose parent is not selected becomes
    /// top-level in the destination list.
    public func bulkMove(_ ids: Set<UUID>, toListId newListId: String) async throws {
        guard lists.contains(where: { $0.id == newListId && $0.deletedAt == nil }) else { return }
        for id in selectedItemRoots(from: ids) {
            guard var copy = items.first(where: { $0.id == id }),
                  copy.listId != newListId else { continue }
            copy.listId = newListId
            copy.section = nil
            if copy.parentId != nil {
                copy.parentId = nil
            }
            try await updateWithSubtreeCascades(copy)
        }
    }

    private func moveDescendantsToList(parentId: UUID, listId: String) async throws {
        for id in itemDescendantIds(of: parentId) {
            guard var copy = items.first(where: { $0.id == id }),
                  copy.listId != listId || copy.section != nil else { continue }
            copy.listId = listId
            copy.section = nil
            try await update(copy)
        }
    }

    /// Assign every selected item to `section` (nil = Others) within their list.
    public func bulkMove(_ ids: Set<UUID>, toSection section: String?) async throws {
        for id in selectedItemRoots(from: ids) {
            guard var copy = items.first(where: { $0.id == id }), copy.section != section else { continue }
            copy.section = section
            try await updateWithSubtreeCascades(copy)
        }
    }

    /// Selected descendants are carried by their selected ancestor's subtree move.
    /// Returning only roots avoids applying the same bulk hierarchy operation twice
    /// in nondeterministic `Set` order.
    private func selectedItemRoots(from ids: Set<UUID>) -> [UUID] {
        ItemHierarchy.selectedRoots(from: ids, in: items)
    }

    /// Every non-deleted descendant item id of `parentId` (children,
    /// grandchildren, …). The item analogue of the list-scoped
    /// `descendantIds(of:)`.
    public func itemDescendantIds(of parentId: UUID) -> [UUID] {
        ItemHierarchy.descendantIds(of: parentId, in: items)
    }

    /// Every descendant item id of `parentId`, including tombstoned items.
    /// Recently Deleted uses this for permanent-delete copy and hard-delete
    /// uses it to remove the whole on-disk subtree.
    public func allItemDescendantIds(of parentId: UUID) -> [UUID] {
        ItemHierarchy.descendantIds(of: parentId, in: items, includingDeleted: true)
    }

    /// Keep a moved item's whole subtree in its section. A child always shares
    /// its parent's section (children render under the parent regardless of
    /// their own `section`), so a move that reassigned only the parent left its
    /// descendants pointing at the OLD section — and deleting that section then
    /// soft-deleted them even though they'd visually followed the move. Call on
    /// every move-to-section so the stored data matches what's on screen.
    public func applySectionCascadeSync(toDescendantsOf parentId: UUID, section: String?) {
        for id in itemDescendantIds(of: parentId) {
            guard let current = items.first(where: { $0.id == id }), current.section != section else { continue }
            var copy = current
            copy.section = section
            applyUpdateSync(copy)
        }
    }

    /// Keep a moved item's whole subtree in its new list. Children render under
    /// their parent regardless of their own `listId`, so a cross-list move that
    /// reassigned only the parent left its descendants written to the OLD list's
    /// folder — orphaned, and swept up if that list is later deleted. Clears each
    /// descendant's `section` too (section ids are scoped to the source list).
    /// Call on every cross-list move so the stored data matches what's on screen.
    public func applyListCascadeSync(toDescendantsOf parentId: UUID, listId: String) {
        for id in itemDescendantIds(of: parentId) {
            guard let current = items.first(where: { $0.id == id }),
                  current.listId != listId || current.section != nil else { continue }
            var copy = current
            copy.listId = listId
            copy.section = nil
            applyUpdateSync(copy)
        }
    }

    public func delete(_ id: UUID) async throws {
        guard items.contains(where: { $0.id == id }) else { return }
        let ids = Set([id] + allItemDescendantIds(of: id))
        let removedItems = items.filter { ids.contains($0.id) }
        for item in removedItems {
            try await deleteItemOrdered(item)
        }
        items.removeAll { ids.contains($0.id) }
        for id in ids {
            await scheduler.cancel(id)
        }
    }

    /// Soft delete: marks an item with `deletedAt = now` and persists. Item
    /// stays on disk so it can be restored from Recently Deleted within 30 days.
    public func softDelete(_ id: UUID) async throws {
        let now = Date()
        let ids = [id] + itemDescendantIds(of: id)
        for targetId in ids {
            guard var item = items.first(where: { $0.id == targetId }),
                  item.deletedAt == nil else { continue }
            item.deletedAt = now
            item.modifiedAt = now
            if let idx = items.firstIndex(where: { $0.id == targetId }) {
                items[idx] = item
            }
            try await writeItemOrdered(item)
            await scheduler.cancel(targetId)
        }
    }

    /// Synchronous UI-bridge variant of `softDelete(_:)`. Used when a transient
    /// inline-edit shell needs to vanish before UIKit tears down the editing
    /// cell; persistence and notification cancellation continue in the
    /// background like other sync bridge paths.
    public func applySoftDeleteSync(_ id: UUID) {
        let now = Date()
        let ids = [id] + itemDescendantIds(of: id)
        var tombstones: [Item] = []
        for targetId in ids {
            guard var item = items.first(where: { $0.id == targetId }),
                  item.deletedAt == nil else { continue }
            item.deletedAt = now
            item.modifiedAt = now
            if let idx = items.firstIndex(where: { $0.id == targetId }) {
                items[idx] = item
            }
            tombstones.append(item)
        }
        guard tombstones.isEmpty == false else { return }
        enqueueDetachedWrite("soft-delete \(id)") { [store, tombstones] in
            for item in tombstones {
                try await store.writeItem(item)
            }
        }
        Task { [scheduler, ids] in
            for targetId in ids {
                await scheduler.cancel(targetId)
            }
        }
    }

    /// Restore: clears `deletedAt`.
    public func restore(_ id: UUID) async throws {
        guard var item = items.first(where: { $0.id == id }) else { return }
        let deletedAt = item.deletedAt
        item.deletedAt = nil
        if !lists.contains(where: { $0.id == item.listId && $0.deletedAt == nil }),
           let fallbackListId = fallbackListIdForRestoredItem() {
            item.listId = fallbackListId
            item.parentId = nil
            item.section = nil
        }
        item = normalizedForStorage(item)
        item.modifiedAt = .now
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
        try await writeItemOrdered(item)
        await scheduler.schedule(item)

        for descendantId in allItemDescendantIds(of: id) {
            guard let idx = items.firstIndex(where: { $0.id == descendantId }),
                  isSameDeletionBatch(items[idx].deletedAt, deletedAt) else { continue }
            var descendant = items[idx]
            descendant.deletedAt = nil
            if let parentId = descendant.parentId,
               let parent = self.item(parentId),
               parent.deletedAt == nil {
                descendant.listId = parent.listId
                descendant.section = parent.section
            }
            descendant = normalizedForStorage(descendant)
            descendant.modifiedAt = .now
            items[idx] = descendant
            try await writeItemOrdered(descendant)
            await scheduler.schedule(descendant)
        }
    }

    // MARK: - Lists

    public func addList(_ list: ItemList) async throws {
        var list = list
        list.parentId = normalizedParentId(for: list)
        list.modifiedAt = .now
        try await writeListOrdered(list)
        lists.append(list)
    }

    public func updateList(_ list: ItemList) async throws {
        var updated = list
        updated.parentId = normalizedParentId(for: updated)
        updated.modifiedAt = .now
        try await writeListOrdered(updated)
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = updated
        } else {
            lists.append(updated)
        }
    }

    private func fallbackListIdForRestoredItem() -> String? {
        if lists.contains(where: { $0.id == ItemList.inboxId && $0.deletedAt == nil }) {
            return ItemList.inboxId
        }
        return lists
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.id < $1.id
            }
            .first?.id
    }

    /// Hard delete: removes the list folder + all items inside.
    public func deleteList(_ id: String) async throws {
        guard let list = lists.first(where: { $0.id == id }) else { return }
        let ids = Set([id] + allDescendantIds(of: id))
        let removedItemIds = items
            .filter { ids.contains($0.listId) }
            .map(\.id)
        try await deleteListOrdered(list)
        lists.removeAll { ids.contains($0.id) }
        items.removeAll { ids.contains($0.listId) }
        for itemId in removedItemIds {
            await scheduler.cancel(itemId)
        }
    }

    /// Soft delete a list: stays on disk, hidden from active views, can be
    /// restored from Recently Deleted. Cascades to descendants — every nested
    /// sub-list also gets `deletedAt = now` so the entire subtree disappears
    /// together and shows up in Recently Deleted as separate restorable rows.
    /// Live items in those lists get the same tombstone so the recovery screen
    /// matches the destructive alert and they can be restored with their list.
    public func softDeleteList(_ id: String) async throws {
        let now = Date()
        let ids = [id] + descendantIds(of: id)
        let idSet = Set(ids)
        for targetId in ids {
            guard var list = lists.first(where: { $0.id == targetId }) else { continue }
            guard list.deletedAt == nil else { continue }
            list.deletedAt = now
            list.modifiedAt = now
            list.lamport += 1
            try await writeListOrdered(list)
            if let idx = lists.firstIndex(where: { $0.id == targetId }) {
                lists[idx] = list
            }
        }
        for idx in items.indices where idSet.contains(items[idx].listId) && items[idx].deletedAt == nil {
            items[idx].deletedAt = now
            items[idx].modifiedAt = now
            let item = items[idx]
            try await writeItemOrdered(item)
            await scheduler.cancel(item.id)
        }
    }

    /// Restore: clears `deletedAt` for the selected list plus any descendant
    /// lists deleted by the same operation. If the restored subtree's parent
    /// is still deleted, the restored root detaches to the sidebar root. Items
    /// deleted by the same list-delete operation are restored with the list;
    /// items and sublists that were already in Recently Deleted stay there.
    public func restoreList(_ id: String) async throws {
        guard let original = lists.first(where: { $0.id == id }) else { return }
        guard original.deletedAt != nil else { return }
        let deletedAt = original.deletedAt
        let restoreIds = [id] + allDescendantIds(of: id).filter { childId in
            guard let list = lists.first(where: { $0.id == childId }) else { return false }
            return isSameDeletionBatch(list.deletedAt, deletedAt)
        }
        let restoreIdSet = Set(restoreIds)

        for targetId in restoreIds {
            guard var list = lists.first(where: { $0.id == targetId }) else { continue }
            list.deletedAt = nil
            list.modifiedAt = .now
            list.lamport += 1
            if let pid = list.parentId,
               restoreIdSet.contains(pid) == false,
               let parent = lists.first(where: { $0.id == pid }),
               parent.deletedAt != nil {
                list.parentId = nil
            }
            try await writeListOrdered(list)
            if let idx = lists.firstIndex(where: { $0.id == targetId }) {
                lists[idx] = list
            }
        }

        let itemRestoreIndexes = items.indices.filter {
            restoreIdSet.contains(items[$0].listId)
                && isSameDeletionBatch(items[$0].deletedAt, deletedAt)
        }
        for idx in itemRestoreIndexes {
            items[idx].deletedAt = nil
            items[idx].modifiedAt = .now
        }
        for idx in itemRestoreIndexes {
            items[idx] = normalizedForStorage(items[idx])
            let item = items[idx]
            try await writeItemOrdered(item)
            await scheduler.schedule(item)
        }
    }

    private func isSameDeletionBatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) < 0.001
    }

    /// Move a list under a new parent (or to root if `newParentId` is nil).
    /// Rejects cycles — the new parent must not be the list itself or one of
    /// its descendants. The on-disk folder is physically moved by
    /// `FileStore.writeList`.
    public func moveList(_ id: String, toParent newParentId: String?) async throws {
        guard var list = lists.first(where: { $0.id == id }) else { return }
        if let newParentId {
            if newParentId == id { return }
            guard let parent = lists.first(where: { $0.id == newParentId }),
                  parent.deletedAt == nil else { return }
            let descendants = Set(descendantIds(of: id))
            if descendants.contains(newParentId) { return }
        }
        list.parentId = newParentId
        list.modifiedAt = .now
        list.lamport += 1
        try await writeListOrdered(list)
        if let idx = lists.firstIndex(where: { $0.id == id }) {
            lists[idx] = list
        }
    }

    /// Store-level guard for list hierarchy writes. UI pickers prevent bad
    /// choices, but local-first data still treats the store as the authority.
    private func normalizedParentId(for list: ItemList) -> String? {
        ListHierarchy.normalizedParentId(for: list, in: lists)
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
        guard lists.contains(where: { $0.id == movedId && $0.deletedAt == nil }) else { return false }

        // Parent/cycle guard — mirror moveList.
        if let newParentId {
            if newParentId == movedId { return false }
            guard let parent = lists.first(where: { $0.id == newParentId }),
                  parent.deletedAt == nil else { return false }
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
        enqueueDetachedWrite("sidebar reorder") { [store, changes] in
            for list in changes {
                try await store.writeList(list)
            }
        }
        return true
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

    /// Synchronous UI-bridge variant of `reorderSections` — same rationale as
    /// `applyReorderItemsSync`. Disk write is queued in the background.
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
        enqueueDetachedWrite("section reorder in \(snapshot.id)") { [store] in
            try await store.writeList(snapshot)
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
            // Re-fetch the live value inside the loop so an edit made during an
            // earlier iteration's await isn't overwritten by this pre-loop
            // snapshot.
            guard var copy = items.first(where: { $0.id == it.id }) else { continue }
            copy.section = newId.uuidString
            try await update(copy)
        }
    }

    // MARK: - Hierarchy helpers

    /// Direct children of `parentId` (non-deleted), sorted by position.
    public func children(of parentId: String?) -> [ItemList] {
        ListHierarchy.children(of: parentId, in: lists)
    }

    /// All descendants of `id` (children, grandchildren, …) — non-deleted.
    /// Used by cascade delete and the cycle guard.
    public func descendantIds(of id: String) -> [String] {
        ListHierarchy.descendantIds(of: id, in: lists)
    }

    /// All descendants of `id`, including deleted lists. Hard-delete and purge
    /// use this because the folder removal is recursive regardless of tombstone
    /// state, so the in-memory snapshot must drop hidden descendants too.
    private func allDescendantIds(of id: String) -> [String] {
        ListHierarchy.descendantIds(of: id, in: lists, includingDeleted: true)
    }

    /// Auto-purge tombstones older than 30 days. Called from bootstrap.
    private func purgeExpiredTombstones() async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        for item in items where (item.deletedAt ?? .distantFuture) < cutoff {
            try? await deleteItemOrdered(item)
        }
        items.removeAll { ($0.deletedAt ?? .distantFuture) < cutoff }

        let expiredListIds = lists
            .filter { ($0.deletedAt ?? .distantFuture) < cutoff }
            .map(\.id)
        for id in expiredListIds where lists.contains(where: { $0.id == id }) {
            try? await deleteList(id)
        }
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
        showPastEvents: Bool = false,
        lingering: Set<UUID> = [],
        now: Date = .now
    ) -> [Item] {
        items
            .filter { item in
                if item.deletedAt != nil { return false }
                if lingering.contains(item.id) { return true }
                if item.isRolledOffPastEvent(now: now) && !showPastEvents { return false }
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
