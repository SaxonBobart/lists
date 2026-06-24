import Foundation
import Testing
@testable import Lists

struct ListEditDraftTests {
    private func makeDraft(parentId: String? = nil) -> ListEditDraft {
        ListEditDraft(
            name: "  Weekend Shop  ",
            icon: "cart.fill",
            color: .green,
            listType: .shopping,
            parentId: parentId
        )
    }

    @Test func newListUsesTrimmedNameParentAndNextPosition() {
        let now = ISO8601.date(from: "2026-06-23T10:00:00.000Z")!

        let list = makeDraft(parentId: "personal")
            .makeList(existing: nil, now: now, nextPosition: 4)

        #expect(list.name == "Weekend Shop")
        #expect(list.icon == "cart.fill")
        #expect(list.color == .green)
        #expect(list.groceryMode)
        #expect(list.defaultItemType == nil)
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

    @Test func legacyDefaultItemTypeStillDecodes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsLegacyDefault-\(UUID().uuidString)")
        let listDir = root.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at: listDir, withIntermediateDirectories: true)
        let yaml = """
        id: work
        name: Work
        icon: briefcase
        color: orange
        default_item_type: event
        created_at: 2026-06-23T10:00:00.000Z
        modified_at: 2026-06-23T10:00:00.000Z
        position: 1.0
        lamport: 0
        """
        try yaml.write(to: listDir.appendingPathComponent(".list.yml"), atomically: true, encoding: .utf8)

        let loaded = try await FileStore(root: root).loadAll()

        #expect(loaded.lists.first?.list.defaultItemType == .event)
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
            defaultItemType: .event,
            groceryMode: false,
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
            listType: .standard,
            parentId: "projects"
        ).makeList(existing: existing, now: modified, nextPosition: 99)

        #expect(list.id == "work")
        #expect(list.name == "Deep Work")
        #expect(list.icon == "hammer.fill")
        #expect(list.color == .teal)
        #expect(!list.groceryMode)
        #expect(list.defaultItemType == .event)
        #expect(list.createdAt == created)
        #expect(list.modifiedAt == modified)
        #expect(list.position == 12)
        #expect(list.parentId == "projects")
        #expect(list.deletedAt == deleted)
        #expect(list.lamport == 42)
    }
}
