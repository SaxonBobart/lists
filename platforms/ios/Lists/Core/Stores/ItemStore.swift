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

    private let store: FileStore
    private let scheduler: NotificationScheduler

    public init(store: FileStore, scheduler: NotificationScheduler = .shared) {
        self.store = store
        self.scheduler = scheduler
    }

    /// First-time bootstrap: ensure the Lists root exists, load whatever is
    /// already on disk, and (if empty) seed sample data.
    public func bootstrap() async throws {
        try await store.ensureRoot()
        let loaded = try await store.loadAll()

        if loaded.isEmpty {
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
            self.lists = loaded.map(\.list)
            self.items = loaded.flatMap(\.items)
        }
        try await purgeExpiredTombstones()
        self.isLoaded = true
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

    public func update(_ item: Item) async throws {
        var updated = item
        updated.modifiedAt = .now
        try await store.writeItem(updated)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.append(updated)
        }
        await scheduler.schedule(updated)
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
