import Testing
@testable import Lists

struct ItemHierarchyTests {
    @Test func allFlattenIncludesArbitraryDepth() {
        let parent = Item(type: .task, title: "Parent", listId: "inbox", sortIndex: 0)
        let child = Item(type: .task, title: "Child", listId: "inbox",
                         parentId: parent.id, sortIndex: 0)
        let grandchild = Item(type: .task, title: "Grandchild", listId: "inbox",
                              parentId: child.id, sortIndex: 0)
        let greatGrandchild = Item(type: .task, title: "Great-grandchild", listId: "inbox",
                                   parentId: grandchild.id, sortIndex: 0)

        let rows = ItemHierarchy.flattenForAll(
            parents: [parent],
            allItems: [greatGrandchild, grandchild, child, parent],
            showCompleted: false,
            showPastEvents: false
        )

        #expect(rows.map { "\($0.indent):\($0.item.title)" } == [
            "0:Parent",
            "1:Child",
            "2:Grandchild",
            "3:Great-grandchild"
        ])
    }

    @Test func allFlattenExcludesHabitsAtAnyDepth() {
        let parent = Item(type: .task, title: "Parent", listId: "inbox", sortIndex: 0)
        let visibleChild = Item(type: .task, title: "Visible child", listId: "inbox",
                                parentId: parent.id, sortIndex: 0)
        let habit = Item(type: .habit, title: "Habit child", listId: "inbox",
                         parentId: parent.id, frequency: .daily, sortIndex: 1)
        let underHabit = Item(type: .task, title: "Under habit", listId: "inbox",
                              parentId: habit.id, sortIndex: 0)

        let rows = ItemHierarchy.flattenForAll(
            parents: [parent],
            allItems: [parent, visibleChild, habit, underHabit],
            showCompleted: false,
            showPastEvents: false
        )

        #expect(rows.map(\.item.title) == ["Parent", "Visible child"])
    }

    @Test func allFlattenLetsJustCompletedDescendantLinger() {
        let parent = Item(type: .task, title: "Parent", listId: "inbox", sortIndex: 0)
        let doneChild = Item(type: .task, title: "Done child", listId: "inbox",
                             parentId: parent.id, done: true, sortIndex: 0)

        let hidden = ItemHierarchy.flattenForAll(
            parents: [parent],
            allItems: [parent, doneChild],
            showCompleted: false,
            showPastEvents: false
        )
        let lingering = ItemHierarchy.flattenForAll(
            parents: [parent],
            allItems: [parent, doneChild],
            showCompleted: false,
            showPastEvents: false,
            lingering: [doneChild.id]
        )

        #expect(hidden.map(\.item.title) == ["Parent"])
        #expect(lingering.map(\.item.title) == ["Parent", "Done child"])
    }

    @Test func ancestorsReturnRootToImmediateParent() {
        let root = Item(type: .task, title: "Root", listId: "inbox")
        let parent = Item(type: .task, title: "Parent", listId: "inbox", parentId: root.id)
        let child = Item(type: .task, title: "Child", listId: "inbox", parentId: parent.id)

        let ancestors = ItemHierarchy.ancestors(of: child, in: [child, parent, root])

        #expect(ancestors.map(\.title) == ["Root", "Parent"])
    }

    @Test func ancestorsStopWhenStoredHierarchyHasCycle() {
        var parent = Item(type: .task, title: "Parent", listId: "inbox")
        let child = Item(type: .task, title: "Child", listId: "inbox", parentId: parent.id)
        parent.parentId = child.id

        let ancestors = ItemHierarchy.ancestors(of: child, in: [child, parent])

        #expect(ancestors.map(\.title) == ["Parent"])
    }
}
