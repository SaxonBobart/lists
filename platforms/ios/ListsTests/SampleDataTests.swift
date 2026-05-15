import Foundation
import Testing
@testable import Lists

@Suite("Sample data + bootstrap")
struct SampleDataTests {

    @Test("Seed creates inbox-only undone tasks (top-level + nested)")
    func seedShape() {
        let items = SampleData.seedItems(inboxId: ItemList.inboxId)
        #expect(items.count > 0)
        for item in items where item.listId == ItemList.inboxId {
            #expect(item.type == Item.ItemType.task)
            #expect(item.done == false)
        }
    }

    @Test("Seed includes a parent item with two sub-items")
    func seedHasNesting() {
        let items = SampleData.seedItems(inboxId: ItemList.inboxId)
        let children = items.filter { $0.parentId != nil }
        #expect(children.count >= 2)
        if let firstChildParent = children.first?.parentId {
            #expect(children.allSatisfy { $0.parentId == firstChildParent })
        }
    }

    @Test("Some seeded TOP-LEVEL items have a due date so Today/Scheduled have something to show")
    func seedTopLevelHasDueDates() {
        let topLevel = SampleData.seedItems(inboxId: ItemList.inboxId).filter { $0.parentId == nil }
        #expect(topLevel.contains(where: { $0.due != nil }),
                "No top-level items have a due date — Today / Scheduled would be empty.")
    }

    @Test("ItemStore.bootstrap on an empty root seeds sample data")
    @MainActor
    func bootstrapSeedsWhenEmpty() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ListsTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.isLoaded)
        #expect(store.lists.contains(where: { $0.id == ItemList.inboxId }))
        #expect(store.items.count > 0)
    }

    @Test("toggleDone flips state + persists")
    @MainActor
    func toggleDonePersists() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ListsTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let underlying = FileStore(root: root)
        let store = ItemStore(store: underlying)
        try await store.bootstrap()

        let firstId = try #require(store.items.first?.id)
        try await store.toggleDone(firstId)
        #expect(store.items.first(where: { $0.id == firstId })?.done == true)

        // Re-load via a fresh ItemStore — proves it persisted.
        let store2 = ItemStore(store: underlying)
        try await store2.bootstrap()
        #expect(store2.items.first(where: { $0.id == firstId })?.done == true)
    }
}
