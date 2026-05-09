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

    public init(store: FileStore) {
        self.store = store
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
        self.isLoaded = true
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
    }

    public func add(_ item: Item) async throws {
        var item = item
        item.modifiedAt = .now
        try await store.writeItem(item)
        items.append(item)
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
    }

    public func delete(_ id: UUID) async throws {
        guard let item = items.first(where: { $0.id == id }) else { return }
        try await store.deleteItem(item)
        items.removeAll { $0.id == id }
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
