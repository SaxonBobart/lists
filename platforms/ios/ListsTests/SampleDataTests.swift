import Foundation
import Testing
@testable import Lists

@Suite("Sample data + bootstrap")
struct SampleDataTests {

    @Test("Seed creates 3 tasks, all in inbox, all undone")
    func seedShape() {
        let items = SampleData.seedItems(for: ItemList.inboxId)
        #expect(items.count == 3)
        for item in items {
            #expect(item.listId == ItemList.inboxId)
            #expect(item.type == .task)
            #expect(item.done == false)
        }
    }

    @Test("All seeded items have a due date so Today/Scheduled have something to show")
    func seedHasDueDates() {
        let items = SampleData.seedItems(for: ItemList.inboxId)
        for item in items {
            #expect(item.due != nil, "\(item.title) is missing a due date")
        }
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
        #expect(store.lists.count == 1)
        #expect(store.lists.first?.id == ItemList.inboxId)
        #expect(store.items.count == 3)
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
