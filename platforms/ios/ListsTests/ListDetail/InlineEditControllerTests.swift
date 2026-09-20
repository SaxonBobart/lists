import Foundation
import Testing
import UIKit
@testable import Lists

@MainActor
struct InlineEditControllerTests {
    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsInlineEdit-\(UUID().uuidString)")
    }

    private func makeList(id: String, name: String) -> ItemList {
        ItemList(
            id: id,
            name: name,
            icon: "tray",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 0
        )
    }

    private func seededStore() async throws -> (store: ItemStore, root: URL) {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return (store, root)
    }

    @Test func openingBlankInlineItemDiscardsItWithoutShowingDetail() async throws {
        let (store, root) = try await seededStore()
        let id = store.addInlineItem(type: .task, listId: "A", section: nil)
        let controller = InlineEditController(itemId: id, store: store)
        var endedId: UUID?
        var didShowDetail = false
        controller.onEndEditing = { endedId = $0 }
        controller.onShowDetail = { didShowDetail = true }

        controller.titleView.text = "  \n"
        controller.requestShowDetail()

        #expect(endedId == id)
        #expect(didShowDetail == false)
        #expect(store.item(id)?.deletedAt != nil)

        try await store.flushPendingWrites()
        let reloaded = ItemStore(store: FileStore(root: root))
        try await reloaded.bootstrap()
        #expect(reloaded.item(id)?.deletedAt != nil)
    }

    @Test func openingNamedInlineItemPersistsAndShowsDetail() async throws {
        let (store, _) = try await seededStore()
        let id = store.addInlineItem(type: .task, listId: "A", section: nil)
        let controller = InlineEditController(itemId: id, store: store)
        var endedId: UUID?
        var didShowDetail = false
        controller.onEndEditing = { endedId = $0 }
        controller.onShowDetail = { didShowDetail = true }

        controller.titleView.text = "Buy milk"
        controller.requestShowDetail()

        #expect(endedId == id)
        #expect(didShowDetail)
        #expect(store.item(id)?.title == "Buy milk")
        #expect(store.item(id)?.deletedAt == nil)
    }
}
