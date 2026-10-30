import Foundation
import Testing
@testable import Lists

struct ListEditDraftTests {
    private func makeDraft(parentId: String? = nil) -> ListEditDraft {
        ListEditDraft(
            name: "  Weekend Shop  ",
            icon: "cart.fill",
            color: .green,
            parentId: parentId
        )
    }

    @Test func listDismissalProtectsMeaningfulChangesAndAllowsReverts() {
        let initial = makeDraft(parentId: "parent")
        var edited = initial
        #expect(!edited.hasChanges(from: initial))
        edited.name = "Weekend Shop"
        #expect(!edited.hasChanges(from: initial))
        edited.name = "Different"
        #expect(edited.hasChanges(from: initial))
        edited = initial
        edited.icon = "star"
        #expect(edited.hasChanges(from: initial))
        edited = initial
        edited.color = .red
        #expect(edited.hasChanges(from: initial))
        edited = initial
        edited.parentId = nil
        #expect(edited.hasChanges(from: initial))
        edited = initial
        #expect(!edited.hasChanges(from: initial))
    }

    @Test @MainActor func listSavesPreserveSectionsAndReferencesAcrossColdReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ListSectionDraft-\(UUID())")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        let sections = [
            ListSection(name: "Later", position: 4),
            ListSection(name: "Now", position: 1)
        ]
        let list = ItemList(id: "sectioned", name: "Sectioned", icon: "folder", color: .blue,
                            createdAt: .now, modifiedAt: .now, position: 17, sections: sections)
        let parent = ItemList(id: "parent", name: "Parent", icon: "folder", color: .green,
                              createdAt: .now, modifiedAt: .now, position: 18)
        try await store.addList(list)
        try await store.addList(parent)
        let item = Item(type: .note, title: "Keep section reference", listId: list.id,
                        section: sections[0].id.uuidString)
        try await store.add(item)
        var current = list
        for changed in [false, true] {
            var draft = ListEditDraft(name: current.name, icon: current.icon,
                                      color: current.color, parentId: current.parentId)
            if changed {
                draft.name = "Renamed"
                draft.icon = "star"
                draft.color = .orange
                draft.parentId = parent.id
            }
            let saved = draft.makeList(existing: current, nextPosition: 99)
            #expect(saved.sections == sections)
            #expect(saved.createdAt == list.createdAt)
            #expect(saved.position == list.position)
            try await store.updateList(saved)
            let cold = ItemStore(store: FileStore(root: root))
            try await cold.bootstrap()
            let loaded = try #require(cold.lists.first { $0.id == list.id })
            #expect(loaded.sections == sections, "IDs, names and stored order must survive list-only edits")
            #expect(cold.item(item.id)?.section == sections[0].id.uuidString)
            #expect(loaded.name == draft.name)
            #expect(loaded.parentId == draft.parentId)
            current = saved
        }
    }

    @Test func newListUsesTrimmedNameParentAndNextPosition() {
        let now = ISO8601.date(from: "2026-06-23T10:00:00.000Z")!

        let list = makeDraft(parentId: "personal")
            .makeList(existing: nil, now: now, nextPosition: 4)

        #expect(list.name == "Weekend Shop")
        #expect(list.icon == "cart.fill")
        #expect(list.color == .green)
        #expect(list.parentId == "personal")
        #expect(list.position == 4)
        #expect(list.createdAt == now)
        #expect(list.modifiedAt == now)
        #expect(list.lamport == 1)
        #expect(!list.id.isEmpty)
    }

    @Test func newListDoesNotWriteLegacyDefaultItemType() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsListDraft-\(UUID().uuidString)")
        let store = FileStore(root: root)
        try await store.ensureRoot()
        let list = makeDraft().makeList(existing: nil, now: .now, nextPosition: 1)

        try await store.writeList(list)
        let url = try await store.listDirectory(for: list.id)
            .appendingPathComponent(".list.yml")
        let yaml = try String(contentsOf: url, encoding: .utf8)

        #expect(!yaml.contains("default_item_type"))
    }

    @Test func unusedDefaultTypeCannotRejectAnOtherwiseValidList() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsLegacyDefault-\(UUID().uuidString)")
        let listDir = root.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at: listDir, withIntermediateDirectories: true)
        let yaml = """
        id: work
        name: Work
        icon: briefcase
        color: orange
        default_item_type: unsupported
        created_at: 2026-06-23T10:00:00.000Z
        modified_at: 2026-06-23T10:00:00.000Z
        position: 1.0
        lamport: 0
        """
        try yaml.write(to: listDir.appendingPathComponent(".list.yml"), atomically: true, encoding: .utf8)

        let loaded = try await FileStore(root: root).loadAll()

        #expect(loaded.quarantined.isEmpty)
        #expect(loaded.lists.first?.list.id == "work")
    }

    @Test func editingListPreservesIdentityCreatedAtPositionDeletedAndIncrementsLamport() {
        let created = ISO8601.date(from: "2026-01-01T10:00:00.000Z")!
        let modified = ISO8601.date(from: "2026-06-23T10:00:00.000Z")!
        let deleted = ISO8601.date(from: "2026-06-20T10:00:00.000Z")!
        let existing = ItemList(
            id: "work",
            name: "Work",
            icon: "briefcase",
            color: .orange,
            createdAt: created,
            modifiedAt: created,
            position: 12,
            parentId: nil,
            deletedAt: deleted,
            lamport: 41
        )

        let list = ListEditDraft(
            name: "Deep Work",
            icon: "hammer.fill",
            color: .teal,
            parentId: "projects"
        ).makeList(existing: existing, now: modified, nextPosition: 99)

        #expect(list.id == "work")
        #expect(list.name == "Deep Work")
        #expect(list.icon == "hammer.fill")
        #expect(list.color == .teal)
        #expect(list.createdAt == created)
        #expect(list.modifiedAt == modified)
        #expect(list.position == 12)
        #expect(list.parentId == "projects")
        #expect(list.deletedAt == deleted)
        #expect(list.lamport == 42)
    }
}
