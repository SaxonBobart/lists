import Foundation
import Testing
@testable import Lists

@Suite("Sample data + bootstrap")
struct SampleDataTests {

    @Test("Seed creates 6 tasks (3 top-level + 1 parent + 2 children), all in inbox, all undone")
    func seedShape() {
        let items = SampleData.seedItems(for: ItemList.inboxId)
        #expect(items.count == 6)
        for item in items {
            #expect(item.listId == ItemList.inboxId)
            #expect(item.type == .task)
            #expect(item.done == false)
        }
    }

    @Test("Seed includes a parent item with two sub-items")
    func seedHasNesting() {
        let items = SampleData.seedItems(for: ItemList.inboxId)
        let parents = items.filter { $0.parentId == nil }
        let children = items.filter { $0.parentId != nil }
        #expect(parents.count == 4)   // 3 unparented + the trip parent
        #expect(children.count == 2)
        // The two children share the same parentId.
        if let firstChildParent = children.first?.parentId {
            #expect(children.allSatisfy { $0.parentId == firstChildParent })
        }
    }

    @Test("All seeded TOP-LEVEL items have a due date so Today/Scheduled have something to show")
    func seedTopLevelHasDueDates() {
        let topLevel = SampleData.seedItems(for: ItemList.inboxId).filter { $0.parentId == nil }
        for item in topLevel {
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
        #expect(store.items.count == 6)
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
