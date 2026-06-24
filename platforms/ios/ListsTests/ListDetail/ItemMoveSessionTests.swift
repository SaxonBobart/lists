import SwiftUI
import Testing
@testable import Lists

@MainActor
struct ItemMoveSessionTests {
    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsMoveSession-\(UUID().uuidString)")
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

    private func seededStore() async throws -> ItemStore {
        let root = freshRoot()
        let setup = FileStore(root: root)
        try await setup.ensureRoot()
        try await setup.writeList(makeList(id: "A", name: "Alpha"))
        try await setup.writeList(makeList(id: "B", name: "Bravo"))

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }

    private func freshDefaults() -> UserDefaults {
        let name = "ListsMoveSessionPrefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func listDetailView(
        store: ItemStore,
        prefs: ListViewPreferences,
        moveSession: ItemMoveSession = ItemMoveSession()
    ) -> ListDetailCollectionView {
        ListDetailCollectionView(
            store: store,
            listId: "A",
            prefs: prefs,
            listColor: .blue,
            bridge: ListDetailBridge(),
            inSelectMode: .constant(false),
            selection: .constant([]),
            editingItemId: .constant(nil),
            editingSectionKey: .constant(nil),
            lingeringIds: [],
            defaultNewItemType: .task,
            moveSession: moveSession,
            onToggleItem: { _ in },
            onIncrementHabit: { _ in },
            onSelectToggle: { _ in },
            onPromptDeleteSection: { _, _ in },
            onSoftDeleteSubList: { _ in },
            onSoftDeleteItem: { _ in },
            onPromoteOthers: { _ in },
            onRenameSection: { _, _ in },
            onShowItemDetail: { _ in },
            onOpenSubList: { _ in },
            onMoveShelfDragCandidateChanged: { _ in },
            onBeginInlineEdit: { _ in },
            onBeginMove: { _ in },
            onEndInlineEdit: { _ in },
            onEndEditSection: {}
        )
    }

    @Test func blocksMovingItemAndItsDescendantsAsParents() async throws {
        let store = try await seededStore()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)

        let session = ItemMoveSession()
        session.begin(item: parent)

        #expect(session.canPickParent(parent.id, in: store) == false)
        #expect(session.canPickParent(child.id, in: store) == false)
    }

    @Test func cannotPickParentWhenNoItemIsAvailableToMove() async throws {
        let store = try await seededStore()
        let moving = Item(type: .task, title: "Moving", listId: "A")
        try await store.add(moving)
        let candidate = Item(type: .task, title: "Candidate", listId: "A")
        try await store.add(candidate)

        let session = ItemMoveSession()

        #expect(session.canPickParent(candidate.id, in: store) == false)
        #expect(session.blockedItemIds(in: store).isEmpty)

        session.begin(item: moving)
        try await store.softDelete(moving.id)

        #expect(session.canPickParent(candidate.id, in: store) == false)
        #expect(session.blockedItemIds(in: store).isEmpty)
    }

    @Test func commitToNoneMakesItemTopLevelInCurrentList() async throws {
        let store = try await seededStore()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)

        let session = ItemMoveSession()
        session.begin(item: child)
        session.commit(toList: "A", parent: nil, store: store)

        #expect(store.item(child.id)?.parentId == nil)
        #expect(store.item(child.id)?.listId == "A")
        #expect(session.isActive == false)
    }

    @Test func commitToNoneInSameListKeepsSection() async throws {
        let store = try await seededStore()
        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let sectionKey = section.id.uuidString
        let parent = Item(type: .task, title: "Parent", listId: "A", section: sectionKey)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: sectionKey, parentId: parent.id)
        try await store.add(child)

        let session = ItemMoveSession()
        session.begin(item: child)
        session.commit(toList: "A", parent: nil, store: store)

        #expect(store.item(child.id)?.parentId == nil)
        #expect(store.item(child.id)?.section == sectionKey)
        #expect(session.isActive == false)
    }

    @Test func moveDestinationFlatteningRevealsCollapsedDescendants() async throws {
        let store = try await seededStore()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)
        let grandchild = Item(type: .task, title: "Grandchild", listId: "A", parentId: child.id)
        try await store.add(grandchild)
        let prefs = ListViewPreferences(defaults: freshDefaults())
        prefs.setItemExpanded(false, itemId: parent.id.uuidString, in: "A")
        let view = listDetailView(store: store, prefs: prefs)

        #expect(view.flattenWithChildren([parent]).map { $0.item.id } == [parent.id])
        #expect(
            view.flattenWithChildren([parent], forceExpanded: true).map { $0.item.id }
                == [parent.id, child.id, grandchild.id]
        )
    }

    @Test func moveModeTemporarilyExpandsCollapsedSections() async throws {
        let store = try await seededStore()
        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let sectionKey = section.id.uuidString
        let moving = Item(type: .task, title: "Moving", listId: "A", section: sectionKey)
        try await store.add(moving)
        let prefs = ListViewPreferences(defaults: freshDefaults())
        prefs.setSectionExpanded(false, sectionId: sectionKey, in: "A")
        let session = ItemMoveSession()
        let view = listDetailView(store: store, prefs: prefs, moveSession: session)

        #expect(view.sectionExpandedForRendering(sectionKey, showHeader: true) == false)

        session.begin(item: moving)

        #expect(view.sectionExpandedForRendering(sectionKey, showHeader: true))
        #expect(view.sectionExpandedForRendering(sectionKey, showHeader: true, draggingKey: sectionKey) == false)
    }

    @Test func deletedMovingItemIsUnavailableAndRefreshCancelsSession() async throws {
        let store = try await seededStore()
        let moving = Item(type: .task, title: "Moving", listId: "A")
        try await store.add(moving)

        let session = ItemMoveSession()
        session.begin(item: moving)
        try await store.softDelete(moving.id)

        #expect(session.movingItem(in: store) == nil)

        session.cancelIfMovingItemUnavailable(in: store)

        #expect(session.isActive == false)
    }

    @Test func invalidDescendantTargetLeavesMoveActiveAndUnchanged() async throws {
        let store = try await seededStore()
        let parent = Item(type: .task, title: "Parent", listId: "A")
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", parentId: parent.id)
        try await store.add(child)

        let session = ItemMoveSession()
        session.begin(item: parent)
        session.commit(toList: "A", parent: child.id, store: store)

        #expect(store.item(parent.id)?.listId == "A")
        #expect(store.item(parent.id)?.parentId == nil)
        #expect(session.isActive)
        #expect(session.isMoving(parent.id))
    }

    @Test func crossListCommitClearsSectionAndCarriesDescendants() async throws {
        let store = try await seededStore()
        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let parent = Item(type: .task, title: "Parent", listId: "A", section: section.id.uuidString)
        try await store.add(parent)
        let child = Item(type: .task, title: "Child", listId: "A", section: section.id.uuidString, parentId: parent.id)
        try await store.add(child)

        let session = ItemMoveSession()
        session.begin(item: parent)
        session.commit(toList: "B", parent: nil, store: store)

        #expect(store.item(parent.id)?.listId == "B")
        #expect(store.item(parent.id)?.section == nil)
        #expect(store.item(child.id)?.listId == "B")
        #expect(session.isActive == false)
    }

    @Test func crossListCommitCanPickParentInDestinationList() async throws {
        let store = try await seededStore()
        let createdSection = try await store.addSection(in: "A", name: "Section A")
        let section = try #require(createdSection)
        let moving = Item(type: .task, title: "Moving", listId: "A", section: section.id.uuidString)
        try await store.add(moving)
        let destinationParent = Item(type: .task, title: "Destination", listId: "B")
        try await store.add(destinationParent)

        let session = ItemMoveSession()
        session.begin(item: moving)
        session.commit(toList: "B", parent: destinationParent.id, store: store)

        #expect(store.item(moving.id)?.listId == "B")
        #expect(store.item(moving.id)?.parentId == destinationParent.id)
        #expect(store.item(moving.id)?.section == nil)
        #expect(session.isActive == false)
    }

    @Test func commitUnderParentInAnotherSectionCarriesSubtreeSection() async throws {
        let store = try await seededStore()
        let createdA = try await store.addSection(in: "A", name: "Section A")
        let createdB = try await store.addSection(in: "A", name: "Section B")
        let sectionA = try #require(createdA)
        let sectionB = try #require(createdB)
        let keyA = sectionA.id.uuidString
        let keyB = sectionB.id.uuidString
        let moving = Item(type: .task, title: "Moving", listId: "A", section: keyA)
        try await store.add(moving)
        let child = Item(type: .task, title: "Child", listId: "A", section: keyA, parentId: moving.id)
        try await store.add(child)
        let destinationParent = Item(type: .task, title: "Destination", listId: "A", section: keyB)
        try await store.add(destinationParent)

        let session = ItemMoveSession()
        session.begin(item: moving)
        session.commit(toList: "A", parent: destinationParent.id, store: store)

        #expect(store.item(moving.id)?.parentId == destinationParent.id)
        #expect(store.item(moving.id)?.section == keyB)
        #expect(store.item(child.id)?.section == keyB)
        #expect(session.isActive == false)
    }

    @Test func crossListCommitUnderParentInheritsDestinationSection() async throws {
        let store = try await seededStore()
        let createdA = try await store.addSection(in: "A", name: "Section A")
        let createdB = try await store.addSection(in: "B", name: "Section B")
        let sectionA = try #require(createdA)
        let sectionB = try #require(createdB)
        let keyA = sectionA.id.uuidString
        let keyB = sectionB.id.uuidString
        let moving = Item(type: .task, title: "Moving", listId: "A", section: keyA)
        try await store.add(moving)
        let child = Item(type: .task, title: "Child", listId: "A", section: keyA, parentId: moving.id)
        try await store.add(child)
        let destinationParent = Item(type: .task, title: "Destination", listId: "B", section: keyB)
        try await store.add(destinationParent)

        let session = ItemMoveSession()
        session.begin(item: moving)
        session.commit(toList: "B", parent: destinationParent.id, store: store)

        #expect(store.item(moving.id)?.listId == "B")
        #expect(store.item(moving.id)?.parentId == destinationParent.id)
        #expect(store.item(moving.id)?.section == keyB)
        #expect(store.item(child.id)?.listId == "B")
        #expect(store.item(child.id)?.section == keyB)
        #expect(session.isActive == false)
    }

    @Test func cannotPickMissingOrDeletedParent() async throws {
        let store = try await seededStore()
        let moving = Item(type: .task, title: "Moving", listId: "A")
        try await store.add(moving)
        var deleted = Item(type: .task, title: "Deleted", listId: "A")
        deleted.deletedAt = .now
        try await store.add(deleted)

        let session = ItemMoveSession()
        session.begin(item: moving)

        #expect(session.canPickParent(UUID(), in: store) == false)
        #expect(session.canPickParent(deleted.id, in: store) == false)
    }

    @Test func commitRejectsParentOutsideDestinationList() async throws {
        let store = try await seededStore()
        let moving = Item(type: .task, title: "Moving", listId: "A")
        try await store.add(moving)
        let sourceListParent = Item(type: .task, title: "Wrong List", listId: "A")
        try await store.add(sourceListParent)

        let session = ItemMoveSession()
        session.begin(item: moving)
        session.commit(toList: "B", parent: sourceListParent.id, store: store)

        #expect(store.item(moving.id)?.listId == "A")
        #expect(store.item(moving.id)?.parentId == nil)
        #expect(session.isActive)
    }

    @Test func commitRejectsMissingOrDeletedDestinationList() async throws {
        let store = try await seededStore()
        let moving = Item(type: .task, title: "Moving", listId: "A")
        try await store.add(moving)
        var deletedList = makeList(id: "deleted", name: "Deleted")
        deletedList.deletedAt = .now
        try await store.addList(deletedList)

        let session = ItemMoveSession()
        session.begin(item: moving)
        session.commit(toList: "missing", parent: nil, store: store)

        #expect(store.item(moving.id)?.listId == "A")
        #expect(session.isActive)

        session.commit(toList: "deleted", parent: nil, store: store)

        #expect(store.item(moving.id)?.listId == "A")
        #expect(session.isActive)
    }

    @Test func shelfDropPayloadResolvesExistingActiveItem() async throws {
        let store = try await seededStore()
        let moving = Item(type: .task, title: "Moving", listId: "A")
        try await store.add(moving)
        let payload = try #require(moving.id.uuidString.data(using: .utf8))

        let resolved = ItemMoveDragPayload.movingItem(
            from: payload,
            store: store
        )

        #expect(resolved?.id == moving.id)
    }

    @Test func shelfDragProviderRegistersLocalItemPayload() async throws {
        let id = UUID()
        let provider = ItemMoveDragPayload.itemProvider(for: id)

        #expect(provider.hasItemConformingToTypeIdentifier(ItemMoveDragPayload.typeIdentifier))

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            provider.loadDataRepresentation(forTypeIdentifier: ItemMoveDragPayload.typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
        }

        #expect(String(data: data, encoding: .utf8) == id.uuidString)
    }

    @Test func shelfDropPayloadRejectsMissingAndDeletedItems() async throws {
        let store = try await seededStore()
        var deleted = Item(type: .task, title: "Deleted", listId: "A")
        deleted.deletedAt = .now
        try await store.add(deleted)
        let missingPayload = try #require(UUID().uuidString.data(using: .utf8))
        let deletedPayload = try #require(deleted.id.uuidString.data(using: .utf8))
        let invalidPayload = try #require("not-a-uuid".data(using: .utf8))

        #expect(ItemMoveDragPayload.movingItem(from: missingPayload, store: store) == nil)
        #expect(ItemMoveDragPayload.movingItem(from: deletedPayload, store: store) == nil)
        #expect(ItemMoveDragPayload.movingItem(from: invalidPayload, store: store) == nil)
    }
}
