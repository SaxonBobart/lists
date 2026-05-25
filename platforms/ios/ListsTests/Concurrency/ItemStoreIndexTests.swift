import XCTest
@testable import Lists

/// PERF-1: ItemStore maintains an id→item index so per-cell lookups are O(1)
/// instead of a linear scan over `items`. The index must stay in sync with the
/// array through every mutation.
@MainActor
final class ItemStoreIndexTests: XCTestCase {

    private func emptyStore() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsIdx-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }

    func testItemLookupMatchesArrayAndIsNilForUnknown() async throws {
        let store = try await emptyStore()
        for item in store.items {
            XCTAssertEqual(store.item(item.id), item)
        }
        XCTAssertNil(store.item(UUID()))
    }

    func testIndexTracksAddToggleAndDelete() async throws {
        let store = try await emptyStore()
        let new = Item(type: .task, title: "Indexed", listId: ItemList.inboxId)

        try await store.add(new)
        XCTAssertEqual(store.item(new.id)?.title, "Indexed")

        try await store.toggleDone(new.id)
        XCTAssertEqual(store.item(new.id)?.done, true)

        try await store.delete(new.id)
        XCTAssertNil(store.item(new.id))
    }
}
