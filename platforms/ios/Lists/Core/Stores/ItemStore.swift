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
            try await store.writeList(inbox)
            let samples = SampleData.seedItems(for: inbox.id)
            for sample in samples {
                try await store.writeItem(sample)
            }
            self.lists = [inbox]
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
    /// restored from Recently Deleted.
    public func softDeleteList(_ id: String) async throws {
        guard var list = lists.first(where: { $0.id == id }) else { return }
        list.deletedAt = .now
        list.modifiedAt = .now
        try await store.writeList(list)
        if let idx = lists.firstIndex(where: { $0.id == id }) {
            lists[idx] = list
        }
    }

    public func restoreList(_ id: String) async throws {
        guard var list = lists.first(where: { $0.id == id }) else { return }
        list.deletedAt = nil
        list.modifiedAt = .now
        try await store.writeList(list)
        if let idx = lists.firstIndex(where: { $0.id == id }) {
            lists[idx] = list
        }
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
    public func items(for query: SmartList, now: Date = .now) -> [Item] {
        items
            .filter { query.matches($0, now: now) }
            .sorted(by: Self.byDue)
    }

    private static func byDue(_ lhs: Item, _ rhs: Item) -> Bool {
        let l = lhs.due ?? .distantFuture
        let r = rhs.due ?? .distantFuture
        if l != r { return l < r }
        return lhs.title < rhs.title
    }
}
