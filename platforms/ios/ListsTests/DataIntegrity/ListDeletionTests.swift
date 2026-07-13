import Foundation
import Testing
@testable import Lists

@MainActor
struct ListDeletionTests {
    private struct NoopNotificationScheduler: NotificationScheduling {
        func schedule(_ item: Item) async {}
        func cancel(_ id: UUID) async {}
    }

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

    private func itemFileURL(for item: Item, root: URL) async throws -> URL {
        let disk = FileStore(root: root)
        _ = try await disk.loadAll()
        let directory = try await disk.listDirectory(for: item.listId)
        return directory.appendingPathComponent(FileStore.documentBaseFileName(for: item))
    }

    private func replaceFileWithDirectory(at url: URL) throws -> Data {
        let original = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return original
    }

    private func restoreFile(_ data: Data, at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
    }

    private func coldItems(at root: URL) async throws -> [Item] {
        let loaded = try await FileStore(root: root).loadAll()
        return loaded.lists.flatMap(\.items)
    }

    private func sameDeletionState(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case (.some(let lhs), .some(let rhs)):
            abs(lhs.timeIntervalSince(rhs)) < 0.001
        default:
            false
        }
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

    @Test func softDeleteListReplaysFailedItemWithoutAnotherDeleteGesture() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let item = Item(type: .task, title: "Child item", listId: "B")
        try await store.add(item)
        let itemURL = try await itemFileURL(for: item, root: root)
        let originalData = try replaceFileWithDirectory(at: itemURL)

        do {
            try await store.softDeleteList("A")
            Issue.record("the sabotaged item write must fail")
        } catch {
            // The two list headers are written before item tombstones.
        }

        let rootDeletedAt = try #require(store.lists.first { $0.id == "A" }?.deletedAt)
        #expect(store.lists.first { $0.id == "B" }?.deletedAt == rootDeletedAt)
        #expect(store.item(item.id)?.deletedAt == nil)

        try restoreFile(originalData, at: itemURL)
        try await store.flushPendingWrites()

        #expect(store.item(item.id)?.deletedAt == rootDeletedAt)
        let cold = try await FileStore(root: root).loadAll()
        let coldRootDate = try #require(
            cold.lists.first { $0.list.id == "A" }?.list.deletedAt
        )
        #expect(abs(coldRootDate.timeIntervalSince(rootDeletedAt)) < 0.001)
        #expect(cold.lists.first { $0.list.id == "B" }?.list.deletedAt == coldRootDate)
        #expect(cold.lists.flatMap(\.items).first { $0.id == item.id }?.deletedAt == coldRootDate)
    }

    @Test func restoringListCancelsItsRetainedDeleteReplay() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let item = Item(type: .task, title: "Child item", listId: "B")
        try await store.add(item)
        let itemURL = try await itemFileURL(for: item, root: root)
        let originalData = try replaceFileWithDirectory(at: itemURL)

        await #expect(throws: (any Error).self) {
            try await store.softDeleteList("A")
        }

        #expect(store.lists.first { $0.id == "A" }?.deletedAt != nil)
        #expect(store.lists.first { $0.id == "B" }?.deletedAt != nil)
        #expect(store.item(item.id)?.deletedAt == nil)

        // Keep the item path sabotaged while restore is accepted. Any queued
        // delete replay may fail again, but restore must retire that intent so
        // it cannot tombstone the live item after the path becomes writable.
        try await store.restoreList("A")
        try restoreFile(originalData, at: itemURL)
        try await store.flushPendingWrites()

        #expect(store.lists.first { $0.id == "A" }?.deletedAt == nil)
        #expect(store.lists.first { $0.id == "B" }?.deletedAt == nil)
        #expect(store.item(item.id)?.deletedAt == nil)

        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.first { $0.list.id == "A" }?.list.deletedAt == nil)
        #expect(cold.lists.first { $0.list.id == "B" }?.list.deletedAt == nil)
        #expect(cold.lists.flatMap(\.items).first { $0.id == item.id }?.deletedAt == nil)
        #expect(try await FileStore(root: root).pendingDeletions().isEmpty)
    }

    @Test func bootstrapFinishesJournaledListDeletionBeforeHierarchyRepair() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let item = Item(type: .task, title: "Child item", listId: "B")
        try await store.add(item)
        let disk = FileStore(root: root)
        _ = try await disk.loadAll()
        let deletedAt = Date.now
        let journal = FileStore.DeletionJournal(
            kind: .list,
            rootId: "A",
            deletedAt: deletedAt
        )
        _ = try await disk.beginDeletion(journal)
        var rootList = try #require(store.lists.first { $0.id == "A" })
        rootList.deletedAt = deletedAt
        rootList.modifiedAt = deletedAt
        rootList.lamport += 1
        try await disk.writeList(rootList)

        let restarted = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
        try await restarted.bootstrap()

        let recoveredRootDate = try #require(
            restarted.lists.first { $0.id == "A" }?.deletedAt
        )
        #expect(abs(recoveredRootDate.timeIntervalSince(deletedAt)) < 0.001)
        let childListDate = try #require(
            restarted.lists.first { $0.id == "B" }?.deletedAt
        )
        let itemDate = try #require(restarted.item(item.id)?.deletedAt)
        #expect(abs(childListDate.timeIntervalSince(recoveredRootDate)) < 0.001)
        #expect(abs(itemDate.timeIntervalSince(recoveredRootDate)) < 0.001)
        #expect(try await FileStore(root: root).pendingDeletions().isEmpty)
    }

    @Test func bootstrapFinishesJournaledItemDeletionBeforeDetachingChildren() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        let child = Item(
            type: .task,
            title: "Child",
            listId: "A",
            parentId: parent.id
        )
        try await store.add(parent)
        try await store.add(child)
        let disk = FileStore(root: root)
        _ = try await disk.loadAll()
        let deletedAt = Date.now
        let journal = FileStore.DeletionJournal(
            kind: .item,
            rootId: parent.id.uuidString,
            deletedAt: deletedAt
        )
        _ = try await disk.beginDeletion(journal)
        var tombstone = parent
        tombstone.deletedAt = deletedAt
        tombstone.modifiedAt = deletedAt
        try await disk.writeItem(tombstone)

        let restarted = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
        try await restarted.bootstrap()

        let recoveredDate = try #require(restarted.item(parent.id)?.deletedAt)
        #expect(abs(recoveredDate.timeIntervalSince(deletedAt)) < 0.001)
        let childDate = try #require(restarted.item(child.id)?.deletedAt)
        #expect(abs(childDate.timeIntervalSince(recoveredDate)) < 0.001)
        #expect(restarted.item(child.id)?.parentId == parent.id)
        #expect(try await FileStore(root: root).pendingDeletions().isEmpty)
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

    @Test func restoreListRetriesFailedItemBeforeRestoringRequestedRoot() async throws {
        let (store, root) = try await seededStoreWithRoot()
        try await store.addList(makeList(id: "C", name: "Charlie", parentId: "A"))

        let oldDeletionDate = Date.now.addingTimeInterval(-86_400)
        var previouslyDeletedList = try #require(store.lists.first { $0.id == "C" })
        previouslyDeletedList.deletedAt = oldDeletionDate
        try await store.updateList(previouslyDeletedList)

        let childItem = Item(type: .task, title: "Child item", listId: "B")
        var previouslyDeletedItem = Item(
            type: .task,
            title: "Previously deleted item",
            listId: "A"
        )
        previouslyDeletedItem.deletedAt = oldDeletionDate
        try await store.add(childItem)
        try await store.add(previouslyDeletedItem)
        try await store.softDeleteList("A")

        let batchDate = try #require(store.lists.first { $0.id == "A" }?.deletedAt)
        let itemURL = try await itemFileURL(for: childItem, root: root)
        let originalData = try replaceFileWithDirectory(at: itemURL)

        do {
            try await store.restoreList("A")
            Issue.record("the sabotaged item restore must fail")
        } catch {
            // Any successful descendant prefix must remain committed, while the
            // requested root stays in Recently Deleted as the retry handle.
        }

        #expect(store.lists.first { $0.id == "A" }?.deletedAt == batchDate)
        #expect(store.deletedLists.contains { $0.id == "A" })
        #expect(store.item(childItem.id)?.deletedAt == batchDate)
        #expect(store.lists.first { $0.id == "C" }?.deletedAt == oldDeletionDate)
        #expect(store.item(previouslyDeletedItem.id)?.deletedAt == oldDeletionDate)

        try restoreFile(originalData, at: itemURL)
        let beforeRetry = try await FileStore(root: root).loadAll()
        let coldLists = beforeRetry.lists.map(\.list)
        let coldItems = beforeRetry.lists.flatMap(\.items)
        for id in ["A", "B", "C"] {
            let memoryDate = store.lists.first { $0.id == id }?.deletedAt
            let diskDate = coldLists.first { $0.id == id }?.deletedAt
            #expect(sameDeletionState(memoryDate, diskDate))
        }
        for id in [childItem.id, previouslyDeletedItem.id] {
            #expect(sameDeletionState(
                store.item(id)?.deletedAt,
                coldItems.first { $0.id == id }?.deletedAt
            ))
        }

        let restarted = ItemStore(store: FileStore(root: root))
        try await restarted.bootstrap()

        #expect(restarted.lists.first { $0.id == "A" }?.deletedAt == nil)
        #expect(restarted.lists.first { $0.id == "B" }?.deletedAt == nil)
        #expect(restarted.lists.first { $0.id == "B" }?.parentId == "A")
        #expect(restarted.item(childItem.id)?.deletedAt == nil)
        #expect(sameDeletionState(
            restarted.lists.first { $0.id == "C" }?.deletedAt,
            oldDeletionDate
        ))
        #expect(sameDeletionState(
            restarted.item(previouslyDeletedItem.id)?.deletedAt,
            oldDeletionDate
        ))
        #expect(try await FileStore(root: root).pendingRestore() == nil)

        let repaired = try await FileStore(root: root).loadAll()
        #expect(repaired.lists.first { $0.list.id == "A" }?.list.deletedAt == nil)
        #expect(repaired.lists.first { $0.list.id == "B" }?.list.deletedAt == nil)
        #expect(repaired.lists.first { $0.list.id == "B" }?.list.parentId == "A")
        #expect(repaired.lists.flatMap(\.items).first { $0.id == childItem.id }?.deletedAt == nil)
        #expect(sameDeletionState(
            repaired.lists.first { $0.list.id == "C" }?.list.deletedAt,
            oldDeletionDate
        ))
        #expect(sameDeletionState(
            repaired.lists.flatMap(\.items)
                .first { $0.id == previouslyDeletedItem.id }?.deletedAt,
            oldDeletionDate
        ))
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

    @Test func softDeleteItemRetriesThroughAlreadyDeletedParentAndChild() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)
        let grandchild = Item(
            type: .task,
            title: "Grandchild",
            listId: "A",
            parentId: child.id
        )
        try await store.add(grandchild)
        let grandchildURL = try await itemFileURL(for: grandchild, root: root)
        let originalData = try replaceFileWithDirectory(at: grandchildURL)

        do {
            try await store.softDelete(parent.id)
            Issue.record("the sabotaged grandchild write must fail")
        } catch {
            // Parent and child form the persisted prefix before this failure.
        }

        let batchDate = try #require(store.item(parent.id)?.deletedAt)
        #expect(store.item(child.id)?.deletedAt == batchDate)
        #expect(store.item(grandchild.id)?.deletedAt == nil)

        try restoreFile(originalData, at: grandchildURL)
        try await store.flushPendingWrites()

        #expect(store.item(parent.id)?.deletedAt == batchDate)
        #expect(store.item(child.id)?.deletedAt == batchDate)
        #expect(store.item(grandchild.id)?.deletedAt == batchDate)
        let cold = try await coldItems(at: root)
        let coldBatchDate = try #require(cold.first { $0.id == parent.id }?.deletedAt)
        #expect(abs(coldBatchDate.timeIntervalSince(batchDate)) < 0.001)
        #expect(cold.first { $0.id == child.id }?.deletedAt == coldBatchDate)
        #expect(cold.first { $0.id == grandchild.id }?.deletedAt == coldBatchDate)
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

    @Test func restoringItemWithoutAnActiveListDoesNotCreateJournal() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let item = Item(type: .task, title: "No destination", listId: "A")
        try await store.add(item)
        try await store.softDeleteList("A")

        await #expect(throws: ItemStore.RestoreError.noAvailableList) {
            try await store.restore(item.id)
        }

        #expect(store.item(item.id)?.deletedAt != nil)
        #expect(try await FileStore(root: root).pendingRestore() == nil)
        try await store.flushPendingWrites()
    }

    @Test func restoreItemResumesLeafPrefixBeforeRestoringRoot() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)
        let grandchild = Item(
            type: .task,
            title: "Grandchild",
            listId: "A",
            parentId: child.id
        )
        try await store.add(grandchild)
        try await store.softDelete(parent.id)

        let batchDate = try #require(store.item(parent.id)?.deletedAt)
        let childURL = try await itemFileURL(for: child, root: root)
        let originalData = try replaceFileWithDirectory(at: childURL)

        do {
            try await store.restore(parent.id)
            Issue.record("the sabotaged child restore must fail")
        } catch {
            // The grandchild is the persisted leaf prefix; its child parent and
            // the requested root stay tombstoned as retry anchors.
        }

        #expect(store.item(parent.id)?.deletedAt == batchDate)
        #expect(store.deletedItems.contains { $0.id == parent.id })
        #expect(store.item(child.id)?.deletedAt == batchDate)
        #expect(store.item(child.id)?.parentId == parent.id)
        #expect(store.item(grandchild.id)?.deletedAt == nil)
        #expect(store.item(grandchild.id)?.parentId == child.id)

        try restoreFile(originalData, at: childURL)
        let beforeRetry = try await coldItems(at: root)
        for id in [parent.id, child.id, grandchild.id] {
            #expect(sameDeletionState(
                store.item(id)?.deletedAt,
                beforeRetry.first { $0.id == id }?.deletedAt
            ))
        }
        #expect(beforeRetry.first { $0.id == child.id }?.parentId == parent.id)
        #expect(beforeRetry.first { $0.id == grandchild.id }?.parentId == child.id)

        let restarted = ItemStore(store: FileStore(root: root))
        try await restarted.bootstrap()

        #expect(restarted.item(parent.id)?.deletedAt == nil)
        #expect(restarted.item(child.id)?.deletedAt == nil)
        #expect(restarted.item(child.id)?.parentId == parent.id)
        #expect(restarted.item(grandchild.id)?.deletedAt == nil)
        #expect(restarted.item(grandchild.id)?.parentId == child.id)
        #expect(try await FileStore(root: root).pendingRestore() == nil)

        let repaired = try await coldItems(at: root)
        #expect(repaired.first { $0.id == parent.id }?.deletedAt == nil)
        #expect(repaired.first { $0.id == child.id }?.deletedAt == nil)
        #expect(repaired.first { $0.id == child.id }?.parentId == parent.id)
        #expect(repaired.first { $0.id == grandchild.id }?.deletedAt == nil)
        #expect(repaired.first { $0.id == grandchild.id }?.parentId == child.id)
    }

    @Test func restoreItemRetryClearsItsReconciledPersistenceFailure() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(
            type: .task,
            title: "Child",
            listId: "A",
            parentId: parent.id
        )
        try await store.add(child)
        try await store.softDelete(parent.id)

        let childURL = try await itemFileURL(for: child, root: root)
        let originalData = try replaceFileWithDirectory(at: childURL)
        await #expect(throws: (any Error).self) {
            try await store.restore(parent.id)
        }

        try restoreFile(originalData, at: childURL)
        try await store.restore(parent.id)
        try await store.flushPendingWrites()
        try await store.reloadFromDisk()

        #expect(store.item(parent.id)?.deletedAt == nil)
        #expect(store.item(child.id)?.deletedAt == nil)
        #expect(store.item(child.id)?.parentId == parent.id)
        #expect(try await FileStore(root: root).pendingRestore() == nil)
    }

    @Test func hardDeleteIsBlockedWhileItemRestoreJournalIsPending() async throws {
        let (store, root) = try await seededStoreWithRoot()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)
        let grandchild = Item(
            type: .task,
            title: "Grandchild",
            listId: "A",
            parentId: child.id
        )
        try await store.add(grandchild)
        try await store.softDelete(parent.id)

        let parentURL = try await itemFileURL(for: parent, root: root)
        let childURL = try await itemFileURL(for: child, root: root)
        let originalData = try replaceFileWithDirectory(at: childURL)
        defer { try? restoreFile(originalData, at: childURL) }

        await #expect(throws: (any Error).self) {
            try await store.restore(parent.id)
        }
        let rootBeforeDelete = try #require(store.item(parent.id))
        let journalBeforeDelete = try #require(
            try await FileStore(root: root).pendingRestore()
        )
        #expect(journalBeforeDelete.kind == .item)
        #expect(journalBeforeDelete.rootId == parent.id.uuidString)

        await #expect(throws: ItemStore.RestoreError.pendingRestoreMustFinish) {
            try await store.delete(parent.id)
        }

        #expect(store.item(parent.id) == rootBeforeDelete)
        let diskRoot = try await FileStore(root: root).readItem(at: parentURL)
        #expect(diskRoot.id == rootBeforeDelete.id)
        #expect(sameDeletionState(diskRoot.deletedAt, rootBeforeDelete.deletedAt))
        let journalAfterDelete = try #require(
            try await FileStore(root: root).pendingRestore()
        )
        #expect(journalAfterDelete.kind == journalBeforeDelete.kind)
        #expect(journalAfterDelete.rootId == journalBeforeDelete.rootId)
        #expect(abs(journalAfterDelete.deletedAt.timeIntervalSince(
            journalBeforeDelete.deletedAt
        )) < 0.001)
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
