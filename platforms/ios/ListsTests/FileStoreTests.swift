import Foundation
import Testing
@testable import Lists

@Suite("FileStore")
struct FileStoreTests {

    /// Each test gets a fresh temp directory; we clean it up afterward.
    private func makeStore() throws -> (FileStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ListsTest-\(UUID().uuidString)", isDirectory: true)
        return (FileStore(root: root), root)
    }

    @Test("Writes a list + item, then loads them back")
    func writeAndLoad() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.ensureRoot()

        let list = ItemList.makeInbox()
        try await store.writeList(list)

        let item = Item(type: .task, title: "Buy bread", listId: list.id, due: .now)
        try await store.writeItem(item)

        let loaded = try await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.list.id == list.id)
        #expect(loaded.first?.items.count == 1)
        #expect(loaded.first?.items.first?.title == "Buy bread")
    }

    @Test("Writing twice overwrites in place")
    func writeIsIdempotent() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.ensureRoot()
        let list = ItemList.makeInbox()
        try await store.writeList(list)

        var item = Item(type: .task, title: "Initial", listId: list.id)
        try await store.writeItem(item)

        item.title = "Updated"
        try await store.writeItem(item)

        let loaded = try await store.loadAll()
        #expect(loaded.first?.items.count == 1)
        #expect(loaded.first?.items.first?.title == "Updated")
    }

    @Test("Empty root yields no lists, no error")
    func emptyRoot() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try await store.ensureRoot()
        let loaded = try await store.loadAll()
        #expect(loaded.isEmpty)
    }

    @Test("Delete removes the .md file")
    func deleteItem() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try await store.ensureRoot()

        let list = ItemList.makeInbox()
        try await store.writeList(list)
        let item = Item(type: .task, title: "doomed", listId: list.id)
        try await store.writeItem(item)

        try await store.deleteItem(item)

        let loaded = try await store.loadAll()
        #expect(loaded.first?.items.isEmpty == true)
    }
}
