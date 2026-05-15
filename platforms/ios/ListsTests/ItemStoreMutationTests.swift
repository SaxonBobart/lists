import Foundation
import Testing
@testable import Lists

@Suite("ItemStore mutations")
struct ItemStoreMutationTests {

    @MainActor
    private func makeStore() -> (ItemStore, FileStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ListsTest-\(UUID().uuidString)", isDirectory: true)
        let underlying = FileStore(root: root)
        let store = ItemStore(store: underlying)
        return (store, underlying, root)
    }

    @Test("add appends + persists")
    @MainActor
    func addAppends() async throws {
        let (store, underlying, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let seedCount = SampleData.seedItems(inboxId: ItemList.inboxId).count
        try await store.bootstrap()
        let new = Item(type: .task, title: "Brand new", listId: ItemList.inboxId)
        try await store.add(new)

        #expect(store.items.count == seedCount + 1)
        #expect(store.items.contains(where: { $0.id == new.id }))

        // Persists to disk — re-load via fresh ItemStore
        let store2 = ItemStore(store: underlying)
        try await store2.bootstrap()
        #expect(store2.items.contains(where: { $0.id == new.id }))
    }

    @Test("update replaces in-memory + on-disk")
    @MainActor
    func updateReplaces() async throws {
        let (store, underlying, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.bootstrap()
        var first = try #require(store.items.first)
        first.title = "Edited title"
        first.flagged = true
        try await store.update(first)

        let after = try #require(store.items.first(where: { $0.id == first.id }))
        #expect(after.title == "Edited title")
        #expect(after.flagged == true)

        let store2 = ItemStore(store: underlying)
        try await store2.bootstrap()
        let reloaded = try #require(store2.items.first(where: { $0.id == first.id }))
        #expect(reloaded.title == "Edited title")
        #expect(reloaded.flagged == true)
    }

    @Test("delete removes in-memory + on-disk")
    @MainActor
    func deleteRemoves() async throws {
        let (store, underlying, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.bootstrap()
        let id = try #require(store.items.first?.id)
        try await store.delete(id)

        #expect(!store.items.contains(where: { $0.id == id }))

        let store2 = ItemStore(store: underlying)
        try await store2.bootstrap()
        #expect(!store2.items.contains(where: { $0.id == id }))
    }
}
