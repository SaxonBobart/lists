import Foundation
import Testing
@testable import Lists

struct ListHierarchyTests {
    private func makeList(
        id: String,
        name: String,
        position: Double,
        parentId: String? = nil,
        deletedAt: Date? = nil
    ) -> ItemList {
        ItemList(
            id: id,
            name: name,
            icon: "folder",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: position,
            parentId: parentId,
            deletedAt: deletedAt
        )
    }

    @Test func flattenedRowsHonorExpansionAndSkipDeletedLists() {
        let root = makeList(id: "work", name: "Work", position: 1)
        let sibling = makeList(id: "home", name: "Home", position: 2)
        let child = makeList(id: "projects", name: "Projects", position: 1, parentId: root.id)
        let grandchild = makeList(id: "launch", name: "Launch", position: 1, parentId: child.id)
        let deleted = makeList(id: "old", name: "Old", position: 2, parentId: root.id, deletedAt: .now)

        let rows = ListHierarchy.flattenedRows(
            in: [grandchild, sibling, deleted, child, root],
            expanded: { $0 == root.id }
        )

        #expect(rows.map { "\($0.depth):\($0.list.id):\($0.hasChildren)" } == [
            "0:work:true",
            "1:projects:true",
            "0:home:false"
        ])
    }

    @Test func flattenedRowsCanHideDraggedSubtree() {
        let root = makeList(id: "work", name: "Work", position: 1)
        let child = makeList(id: "projects", name: "Projects", position: 1, parentId: root.id)
        let grandchild = makeList(id: "launch", name: "Launch", position: 1, parentId: child.id)

        let rows = ListHierarchy.flattenedRows(
            in: [root, child, grandchild],
            expanded: { _ in true },
            excludingSubtree: child.id
        )

        #expect(rows.map(\.id) == [root.id])
    }

    @Test func normalizedParentRejectsSelfDescendantAndDeletedParent() {
        let root = makeList(id: "work", name: "Work", position: 1)
        let child = makeList(id: "projects", name: "Projects", position: 1, parentId: root.id)
        let deleted = makeList(id: "archive", name: "Archive", position: 2, deletedAt: .now)

        var selfParent = root
        selfParent.parentId = root.id
        var descendantParent = root
        descendantParent.parentId = child.id
        var deletedParent = child
        deletedParent.parentId = deleted.id

        #expect(ListHierarchy.normalizedParentId(for: selfParent, in: [root, child, deleted]) == nil)
        #expect(ListHierarchy.normalizedParentId(for: descendantParent, in: [root, child, deleted]) == nil)
        #expect(ListHierarchy.normalizedParentId(for: deletedParent, in: [root, child, deleted]) == nil)
        #expect(ListHierarchy.normalizedParentId(for: child, in: [root, child, deleted]) == root.id)
    }

    @Test func canNestRejectsCyclesAndDepthOverflow() {
        let root = makeList(id: "work", name: "Work", position: 1)
        let child = makeList(id: "projects", name: "Projects", position: 1, parentId: root.id)
        let grandchild = makeList(id: "launch", name: "Launch", position: 1, parentId: child.id)
        let source = makeList(id: "personal", name: "Personal", position: 2)
        let sourceChild = makeList(id: "health", name: "Health", position: 1, parentId: source.id)
        let lists = [root, child, grandchild, source, sourceChild]

        #expect(ListHierarchy.canNest(source.id, inside: root.id, in: lists, maxDepth: 2))
        #expect(!ListHierarchy.canNest(source.id, inside: child.id, in: lists, maxDepth: 2))
        #expect(!ListHierarchy.canNest(root.id, inside: grandchild.id, in: lists, maxDepth: 3))
        #expect(!ListHierarchy.canNest(source.id, inside: source.id, in: lists, maxDepth: 3))
    }
}
