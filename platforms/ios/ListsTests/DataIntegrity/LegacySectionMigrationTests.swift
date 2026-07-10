import Foundation
import Testing
@testable import Lists

@MainActor
struct LegacySectionMigrationTests {
    private func freshRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsLegacySections-\(UUID().uuidString)")
    }

    private func makeList(id: String, sections: [ListSection] = []) -> ItemList {
        ItemList(
            id: id,
            name: "Legacy sections",
            icon: "tray",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 0,
            sections: sections
        )
    }

    @Test
    func bootstrapResumesItemsLeftBehindByAnInterruptedMigration() async throws {
        let root = freshRoot()
        let fileStore = FileStore(root: root)
        try await fileStore.ensureRoot()
        let focusId = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000F0"))
        let focus = ListSection(id: focusId, name: "Focus", position: 1_000)
        let list = makeList(id: "legacy-resume", sections: [focus])
        let stranded = Item(
            type: .task,
            title: "Still grouped",
            listId: list.id,
            section: focus.name
        )
        try await fileStore.writeList(list)
        try await fileStore.writeItem(stranded)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        #expect(store.item(stranded.id)?.section == focus.id.uuidString)
        #expect(store.lists.first { $0.id == list.id }?.sections == [focus])
        let cold = try await FileStore(root: root).loadAll()
        #expect(cold.lists.flatMap(\.items).first { $0.id == stranded.id }?.section == focus.id.uuidString)

        let restarted = ItemStore(store: FileStore(root: root))
        try await restarted.bootstrap()
        #expect(restarted.item(stranded.id)?.section == focus.id.uuidString)
        #expect(restarted.lists.first { $0.id == list.id }?.sections == [focus])
    }

    @Test
    func bootstrapCreatesOneDurableSectionPerLegacyName() async throws {
        let root = freshRoot()
        let fileStore = FileStore(root: root)
        try await fileStore.ensureRoot()
        let list = makeList(id: "legacy-happy")
        let firstFocus = Item(
            type: .task,
            title: "First focus item",
            listId: list.id,
            section: "Focus"
        )
        let later = Item(
            type: .task,
            title: "Later item",
            listId: list.id,
            section: "Later"
        )
        let secondFocus = Item(
            type: .task,
            title: "Second focus item",
            listId: list.id,
            section: "Focus"
        )
        try await fileStore.writeList(list)
        try await fileStore.writeItem(firstFocus)
        try await fileStore.writeItem(later)
        try await fileStore.writeItem(secondFocus)

        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let migratedList = try #require(store.lists.first { $0.id == list.id })
        let focus = try #require(migratedList.sections.first { $0.name == "Focus" })
        let laterSection = try #require(migratedList.sections.first { $0.name == "Later" })
        #expect(migratedList.sections.filter { $0.name == "Focus" }.count == 1)
        #expect(migratedList.sections.filter { $0.name == "Later" }.count == 1)
        #expect(store.item(firstFocus.id)?.section == focus.id.uuidString)
        #expect(store.item(secondFocus.id)?.section == focus.id.uuidString)
        #expect(store.item(later.id)?.section == laterSection.id.uuidString)

        let cold = try await FileStore(root: root).loadAll()
        let coldItems = cold.lists.flatMap(\.items)
        #expect(coldItems.first { $0.id == firstFocus.id }?.section == focus.id.uuidString)
        #expect(coldItems.first { $0.id == secondFocus.id }?.section == focus.id.uuidString)
        #expect(coldItems.first { $0.id == later.id }?.section == laterSection.id.uuidString)
    }
}
