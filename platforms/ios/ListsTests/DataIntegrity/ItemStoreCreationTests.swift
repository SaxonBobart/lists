import Foundation
import Testing
@testable import Lists

@MainActor
struct ItemStoreCreationTests {
    private enum AddOutcome: Equatable, Sendable {
        case added
        case duplicate
        case other(String)
    }

    private func makeStore() async throws -> (ItemStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsCreation-\(UUID().uuidString)")
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(.makeInbox())
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return (store, root)
    }

    private func makeList(id: String, name: String) -> ItemList {
        ItemList(
            id: id,
            name: name,
            icon: "tray",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 1
        )
    }

    private func attemptAdd(_ item: Item, to store: ItemStore) async -> AddOutcome {
        do {
            try await store.add(item)
            return .added
        } catch ItemStore.CreationError.duplicateItemID(_) {
            return .duplicate
        } catch {
            return .other(String(describing: error))
        }
    }

    @Test
    func duplicateItemIdIsRejectedWithoutChangingMemoryOrDisk() async throws {
        let (store, root) = try await makeStore()
        let otherList = makeList(id: "other-list", name: "Other")
        try await store.addList(otherList)

        let id = UUID()
        let original = Item(id: id, type: .task, title: "Original", listId: ItemList.inboxId)
        let duplicate = Item(id: id, type: .note, title: "Replacement", listId: otherList.id)
        try await store.add(original)

        do {
            try await store.add(duplicate)
            Issue.record("duplicate item creation must fail")
        } catch let error as ItemStore.CreationError {
            #expect(error == .duplicateItemID(id))
        }
        try await store.flushPendingWrites()

        let live = store.items.filter { $0.id == id }
        #expect(live.count == 1)
        #expect(live.first?.title == original.title)
        #expect(live.first?.type == original.type)
        #expect(live.first?.listId == original.listId)
        let cold = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).filter { $0.id == id }
        #expect(cold.count == 1)
        #expect(cold.first?.title == original.title)
        #expect(cold.first?.listId == original.listId)
    }

    @Test
    func duplicateListIdCannotMoveOrOverwriteTheOriginalFolder() async throws {
        let (store, root) = try await makeStore()
        let original = makeList(id: "stable-list", name: "Original List")
        try await store.addList(original)
        let item = Item(type: .task, title: "Keep me", listId: original.id)
        try await store.add(item)

        var replacement = makeList(id: original.id, name: "Replacement List")
        replacement.color = .red
        replacement.parentId = ItemList.inboxId
        do {
            try await store.addList(replacement)
            Issue.record("duplicate list creation must fail")
        } catch let error as ItemStore.CreationError {
            #expect(error == .duplicateListID(original.id))
        }
        try await store.flushPendingWrites()

        #expect(store.lists.filter { $0.id == original.id }.map(\.name) == [original.name])
        #expect(store.item(item.id)?.listId == original.id)
        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.filter { $0.list.id == original.id }.map(\.list.name) == [original.name])
        #expect(cold.lists.flatMap(\.items).contains { $0.id == item.id })
    }

    @Test
    func tombstonesContinueToReserveTheirIdentities() async throws {
        let (store, _) = try await makeStore()
        let item = Item(type: .task, title: "Deleted item", listId: ItemList.inboxId)
        try await store.add(item)
        try await store.softDelete(item.id)
        let list = makeList(id: "deleted-list", name: "Deleted List")
        try await store.addList(list)
        try await store.softDeleteList(list.id)

        do {
            try await store.add(Item(
                id: item.id,
                type: .task,
                title: "Reused item id",
                listId: ItemList.inboxId
            ))
            Issue.record("a tombstoned item id must remain reserved")
        } catch let error as ItemStore.CreationError {
            #expect(error == .duplicateItemID(item.id))
        }
        do {
            try await store.addList(makeList(id: list.id, name: "Reused list id"))
            Issue.record("a tombstoned list id must remain reserved")
        } catch let error as ItemStore.CreationError {
            #expect(error == .duplicateListID(list.id))
        }

        #expect(store.items.filter { $0.id == item.id }.count == 1)
        #expect(store.item(item.id)?.deletedAt != nil)
        #expect(store.lists.filter { $0.id == list.id }.count == 1)
        #expect(store.lists.first { $0.id == list.id }?.deletedAt != nil)
    }

    @Test
    func concurrentSameIdCreatesPermitExactlyOneValue() async throws {
        let (store, root) = try await makeStore()
        let id = UUID()
        let first = Item(id: id, type: .task, title: "First", listId: ItemList.inboxId)
        let second = Item(id: id, type: .task, title: "Second", listId: ItemList.inboxId)

        async let firstOutcome = attemptAdd(first, to: store)
        async let secondOutcome = attemptAdd(second, to: store)
        let pair = await (firstOutcome, secondOutcome)
        let outcomes = [pair.0, pair.1]

        #expect(outcomes.filter { $0 == .added }.count == 1)
        #expect(outcomes.filter { $0 == .duplicate }.count == 1)
        #expect(outcomes.contains { if case .other = $0 { true } else { false } } == false)
        #expect(store.items.filter { $0.id == id }.count == 1)

        let cold = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).filter { $0.id == id }
        #expect(cold.count == 1)
        #expect(Set(cold.map(\.title)).isSubset(of: [first.title, second.title]))
    }
}
