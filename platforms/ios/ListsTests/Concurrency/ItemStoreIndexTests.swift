import Foundation
import Testing
@testable import Lists

/// ItemStore maintains an id-to-item index so per-cell lookups are O(1) instead
/// of a linear scan over `items`. The index must stay in sync with the array
/// through every mutation.
@MainActor
struct ItemStoreIndexTests {

    private func emptyStore() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsIdx-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }

    @Test func itemLookupMatchesArrayAndIsNilForUnknown() async throws {
        let store = try await emptyStore()
        for item in store.items {
            #expect(store.item(item.id) == item)
        }
        #expect(store.item(UUID()) == nil)
    }

    @Test func indexTracksAddToggleAndDelete() async throws {
        let store = try await emptyStore()
        let new = Item(type: .task, title: "Indexed", listId: ItemList.inboxId)

        try await store.add(new)
        #expect(store.item(new.id)?.title == "Indexed")

        try await store.toggleDone(new.id)
        #expect(store.item(new.id)?.done == true)

        try await store.delete(new.id)
        #expect(store.item(new.id) == nil)
    }
}
