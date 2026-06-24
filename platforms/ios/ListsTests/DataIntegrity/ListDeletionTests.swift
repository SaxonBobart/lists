import Foundation
import Testing
@testable import Lists

@MainActor
struct ListDeletionTests {
    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsDeletion-\(UUID().uuidString)")
    }

    private func makeList(id: String, name: String, parentId: String? = nil) -> ItemList {
        var list = ItemList(
            id: id,
            name: name,
            icon: "tray",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 0
        )
        list.parentId = parentId
        return list
    }

    private func seededStoreWithRoot() async throws -> (store: ItemStore, root: URL) {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo", parentId: "A"))
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return (store, root)
    }

    private func seededStore() async throws -> ItemStore {
        let result = try await seededStoreWithRoot()
        return result.store
    }

    @Test func softDeleteListTombstonesItemsInListAndDescendantLists() async throws {
        let store = try await seededStore()
        let parentItem = Item(type: .task, title: "Parent item", listId: "A")
        let childItem = Item(type: .task, title: "Child item", listId: "B")
        try await store.add(parentItem)
        try await store.add(childItem)

        try await store.softDeleteList("A")

        #expect(store.lists.first { $0.id == "A" }?.deletedAt != nil)
        #expect(store.lists.first { $0.id == "B" }?.deletedAt != nil)
        #expect(store.item(parentItem.id)?.deletedAt != nil)
        #expect(store.item(childItem.id)?.deletedAt != nil)
        #expect(Set(store.deletedItems.map(\.id)) == [parentItem.id, childItem.id])
    }

    @Test func restoreListRestoresDescendantListsAndOnlyItemsDeletedWithThatList() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let liveItem = Item(type: .task, title: "Live", listId: "A")
        let childItem = Item(type: .task, title: "Child", listId: "B")
        var previouslyDeleted = Item(type: .task, title: "Already deleted", listId: "A")
        previouslyDeleted.deletedAt = Date(timeIntervalSince1970: 100)
        try await store.add(liveItem)
        try await store.add(childItem)
        try await store.add(previouslyDeleted)

        try await store.softDeleteList("A")
        try await store.restoreList("A")

        #expect(store.lists.first { $0.id == "A" }?.deletedAt == nil)
        #expect(store.lists.first { $0.id == "B" }?.deletedAt == nil)
        #expect(store.item(liveItem.id)?.deletedAt == nil)
        #expect(store.item(childItem.id)?.deletedAt == nil)
        #expect(store.item(previouslyDeleted.id)?.deletedAt != nil)

        let reloaded = ItemStore(store: FileStore(root: root))
        try await reloaded.bootstrap()
        #expect(reloaded.lists.first { $0.id == "B" }?.deletedAt == nil)
        #expect(reloaded.item(childItem.id)?.deletedAt == nil)
    }

    @Test func restoreListKeepsItemHierarchyWhenChildLoadedBeforeParent() async throws {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        let parentId = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let childId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let parent = Item(id: parentId, type: .task, title: "Parent", listId: "A")
        let child = Item(id: childId, type: .task, title: "Child", listId: "A", parentId: parentId)
        try await setup.writeItem(child)
        try await setup.writeItem(parent)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        let childIndex = try #require(store.items.firstIndex { $0.id == childId })
        let parentIndex = try #require(store.items.firstIndex { $0.id == parentId })
        #expect(childIndex < parentIndex)

        try await store.softDeleteList("A")
        try await store.restoreList("A")

        #expect(store.item(parentId)?.deletedAt == nil)
        #expect(store.item(childId)?.deletedAt == nil)
        #expect(store.item(childId)?.parentId == parentId)
    }

    @Test func restoreChildListDetachesWhenParentStillDeleted() async throws {
        let store = try await seededStore()
        let childItem = Item(type: .task, title: "Child", listId: "B")
        try await store.add(childItem)

        try await store.softDeleteList("A")
        try await store.restoreList("B")

        #expect(store.lists.first { $0.id == "A" }?.deletedAt != nil)
        #expect(store.lists.first { $0.id == "B" }?.deletedAt == nil)
        #expect(store.lists.first { $0.id == "B" }?.parentId == nil)
        #expect(store.item(childItem.id)?.deletedAt == nil)
    }

    @Test func restoreListLeavesPreviouslyDeletedDescendantListDeleted() async throws {
        let store = try await seededStore()
        var child = try #require(store.lists.first { $0.id == "B" })
        child.deletedAt = Date(timeIntervalSince1970: 100)
        try await store.updateList(child)

        try await store.softDeleteList("A")
        try await store.restoreList("A")

        #expect(store.lists.first { $0.id == "A" }?.deletedAt == nil)
        #expect(store.lists.first { $0.id == "B" }?.deletedAt != nil)
        #expect(store.lists.first { $0.id == "B" }?.parentId == "A")
    }

    @Test func restoreItemDetachesFromDeletedParent() async throws {
        let store = try await seededStore()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)
        try await store.softDelete(parent.id)
        try await store.softDelete(child.id)

        try await store.restore(child.id)

        #expect(store.item(child.id)?.deletedAt == nil)
        #expect(store.item(child.id)?.parentId == nil)
        #expect(store.item(child.id)?.listId == "A")
    }

    @Test func restoreItemMovesFromDeletedListToLiveFallbackList() async throws {
        let store = try await seededStore()
        try await store.addList(makeList(id: "C", name: "Catch"))
        let item = Item(type: .task, title: "List item", listId: "A")
        try await store.add(item)
        try await store.softDeleteList("A")

        try await store.restore(item.id)

        #expect(store.item(item.id)?.deletedAt == nil)
        #expect(store.item(item.id)?.listId == "C")
        #expect(store.item(item.id)?.parentId == nil)
        #expect(store.item(item.id)?.section == nil)
    }

    @Test func restoreItemFromDeletedListMovesDescendantsToFallbackWithParent() async throws {
        let store = try await seededStore()
        try await store.addList(makeList(id: "C", name: "Catch"))
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)
        try await store.softDeleteList("A")

        try await store.restore(parent.id)

        #expect(store.item(parent.id)?.deletedAt == nil)
        #expect(store.item(parent.id)?.listId == "C")
        #expect(store.item(child.id)?.deletedAt == nil)
        #expect(store.item(child.id)?.listId == "C")
        #expect(store.item(child.id)?.parentId == parent.id)
    }

    @Test func softDeleteItemTombstonesDescendants() async throws {
        let store = try await seededStore()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)
        let grandchild = Item(type: .task, title: "Grandchild", listId: "A", parentId: child.id)
        try await store.add(grandchild)

        try await store.softDelete(parent.id)

        #expect(store.item(parent.id)?.deletedAt != nil)
        #expect(store.item(child.id)?.deletedAt != nil)
        #expect(store.item(grandchild.id)?.deletedAt != nil)
    }

    @Test func restoreItemRestoresDescendantsDeletedWithIt() async throws {
        let store = try await seededStore()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)

        try await store.softDelete(parent.id)
        try await store.restore(parent.id)

        #expect(store.item(parent.id)?.deletedAt == nil)
        #expect(store.item(child.id)?.deletedAt == nil)
        #expect(store.item(child.id)?.parentId == parent.id)
    }

    @Test func hardDeleteItemRemovesDeletedDescendantsFromMemoryAndDisk() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)
        try await store.softDelete(parent.id)

        try await store.delete(parent.id)

        #expect(store.item(parent.id) == nil)
        #expect(store.item(child.id) == nil)

        let reloaded = ItemStore(store: FileStore(root: root))
        try await reloaded.bootstrap()
        #expect(reloaded.item(parent.id) == nil)
        #expect(reloaded.item(child.id) == nil)
    }

    @Test func hardDeleteListRemovesDescendantListsAndItemsFromMemory() async throws {
        let store = try await seededStore()
        let parentItem = Item(type: .task, title: "Parent item", listId: "A")
        let childItem = Item(type: .task, title: "Child item", listId: "B")
        try await store.add(parentItem)
        try await store.add(childItem)

        try await store.deleteList("A")

        #expect(!store.lists.contains { $0.id == "A" })
        #expect(!store.lists.contains { $0.id == "B" })
        #expect(store.item(parentItem.id) == nil)
        #expect(store.item(childItem.id) == nil)
    }

    @Test func hardDeleteListRemovesAlreadyDeletedDescendantListFromMemory() async throws {
        let store = try await seededStore()
        let childItem = Item(type: .task, title: "Child item", listId: "B")
        try await store.add(childItem)
        var child = try #require(store.lists.first { $0.id == "B" })
        child.deletedAt = .now
        try await store.updateList(child)

        try await store.deleteList("A")

        #expect(!store.lists.contains { $0.id == "B" })
        #expect(store.item(childItem.id) == nil)
    }
}
