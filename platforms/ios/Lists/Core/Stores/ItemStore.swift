import Foundation
import Observation

/// Main-actor coordinator over `FileStore`. Owns the in-memory snapshot of
/// lists + items the UI binds to.
@MainActor
@Observable
public final class ItemStore {
    public private(set) var lists: [ItemList] = []
    public private(set) var items: [Item] = []
    public private(set) var isLoaded: Bool = false
    /// Original paths of files that failed to load and were quarantined on the
    /// last `bootstrap` (DI-1). Drives the "some notes couldn't be opened"
    /// banner; empty on a clean load.
    public private(set) var loadIssues: [String] = []

    private let store: FileStore
    private let scheduler: NotificationScheduler

    public init(store: FileStore, scheduler: NotificationScheduler = .shared) {
        self.store = store
        self.scheduler = scheduler
    }

    /// First-time bootstrap: ensure the Lists root exists, load whatever is
    /// already on disk, and (if empty) seed sample data.
    public func bootstrap() async throws {
        // Always finish "loading", even on a partial failure: showing an empty
        // sidebar + a banner beats hanging forever on "Loading…" (DI-1).
        defer { self.isLoaded = true }
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
        item.done.toggle()
        item.completedAt = item.done ? .now : nil
        item.modifiedAt = .now
        try await store.writeItem(item)
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
        if item.done {
            await scheduler.cancel(item.id)
        } else {
            await scheduler.schedule(item)
        }
    }

    /// Increment a habit's count for the current cycle (capped at goalPerCycle).
    /// No-op for non-habit items.
    public func incrementHabit(_ id: UUID, now: Date = .now) async throws {
        guard var item = items.first(where: { $0.id == id }), item.type == .habit else { return }
        let key = HabitCycle.key(for: item.frequency ?? .daily, on: now)
        let current = item.completionLog[key] ?? 0
        let next = min(current + 1, item.goalPerCycle)
        if next == current { return }
        item.completionLog[key] = next
        item.modifiedAt = .now
        try await store.writeItem(item)
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
    }

    /// Set a habit's count for a specific cycle (used by edit-history flows).
    public func setHabitCount(_ id: UUID, count: Int, on date: Date) async throws {
        guard var item = items.first(where: { $0.id == id }), item.type == .habit else { return }
        let key = HabitCycle.key(for: item.frequency ?? .daily, on: date)
        let clamped = max(0, min(count, item.goalPerCycle))
        if clamped == 0 {
            item.completionLog.removeValue(forKey: key)
        } else {
            item.completionLog[key] = clamped
        }
        item.modifiedAt = .now
        try await store.writeItem(item)
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
    }

    public func add(_ item: Item) async throws {
        var item = item
        item.modifiedAt = .now
        try await store.writeItem(item)
        items.append(item)
        await scheduler.schedule(item)
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
        if let oldListId, oldListId != updated.listId {
            try await store.moveItem(updated, fromListId: oldListId)
        } else {
            try await store.writeItem(updated)
        }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.append(updated)
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
        for item in affected {
            var copy = item
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
        for item in affected {
            var copy = item
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
        try await store.writeItem(item)
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
        await scheduler.cancel(id)
    }

    /// Restore: clears `deletedAt`.
    public func restore(_ id: UUID) async throws {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.deletedAt = nil
        item.modifiedAt = .now
        try await store.writeItem(item)
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
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
