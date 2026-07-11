import Foundation
import Testing
@testable import Lists

@MainActor
struct ItemCompletionLingerTests {
    private func makeStore() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsLinger-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }

    @Test func toggleStartsLingerWhenCompletingHiddenRow() async throws {
        let store = try await makeStore()
        let item = Item(type: .task, title: "Done soon", listId: ItemList.inboxId)
        try await store.add(item)
        let transition = try await ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: false
        )

        #expect(transition == .start)
        #expect(store.item(item.id)?.done == true)
    }

    @Test func toggleDoesNotLingerWhenCompletedRowsAreVisible() async throws {
        let store = try await makeStore()
        let item = Item(type: .task, title: "Visible done", listId: ItemList.inboxId)
        try await store.add(item)
        let transition = try await ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: true
        )

        #expect(transition == .remove)
    }

    @Test func habitIncrementStartsLingerWhenGoalIsReached() async throws {
        let store = try await makeStore()
        let habit = Item(
            type: .habit,
            title: "Water",
            listId: ItemList.inboxId,
            frequency: .daily,
            goalPerCycle: 1
        )
        try await store.add(habit)
        let transition = try await ItemCompletionLinger.incrementHabit(
            habit,
            store: store,
            showCompleted: false
        )

        #expect(transition == .start)
        #expect(store.item(habit.id)?.completions.count == 1)
    }

    @Test func habitIncrementDoesNotLingerWhenCompletedRowsAreVisible() async throws {
        let store = try await makeStore()
        let habit = Item(
            type: .habit,
            title: "Water",
            listId: ItemList.inboxId,
            frequency: .daily,
            goalPerCycle: 1
        )
        try await store.add(habit)
        let transition = try await ItemCompletionLinger.incrementHabit(
            habit,
            store: store,
            showCompleted: true
        )

        #expect(transition == .none)
    }

    @Test func uncompletingRequestsImmediateLingerRemoval() async throws {
        let store = try await makeStore()
        let item = Item(
            type: .task,
            title: "Undo",
            listId: ItemList.inboxId,
            done: true,
            completedAt: .now
        )
        try await store.add(item)

        let transition = try await ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: false
        )

        #expect(transition == .remove)
        #expect(store.item(item.id)?.done == false)
    }
}
