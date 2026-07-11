import Testing
@testable import Lists

@Suite("List detail section dividers")
struct ListDetailSectionDividerTests {
    @Test("The first section starts clean when there are no sublists")
    func firstSectionWithoutSublists() {
        #expect(!ListDetailCollectionView.sectionHeaderShowsTopDivider(
            key: "tasks",
            orderedSectionKeys: ["tasks", "notes"],
            hasSubLists: false
        ))
        #expect(ListDetailCollectionView.sectionHeaderShowsTopDivider(
            key: "notes",
            orderedSectionKeys: ["tasks", "notes"],
            hasSubLists: false
        ))
    }

    @Test("Sublists are separated from the first item section")
    func firstSectionWithSublists() {
        #expect(ListDetailCollectionView.sectionHeaderShowsTopDivider(
            key: "tasks",
            orderedSectionKeys: ["tasks", "notes"],
            hasSubLists: true
        ))
    }

    @Test("Divider ownership follows reordered sections")
    func reorderedSections() {
        let order = ["notes", "tasks"]
        #expect(!ListDetailCollectionView.sectionHeaderShowsTopDivider(
            key: "notes",
            orderedSectionKeys: order,
            hasSubLists: false
        ))
        #expect(ListDetailCollectionView.sectionHeaderShowsTopDivider(
            key: "tasks",
            orderedSectionKeys: order,
            hasSubLists: false
        ))
    }
}
