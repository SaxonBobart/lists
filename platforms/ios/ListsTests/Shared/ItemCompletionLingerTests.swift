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
        var lingering: Set<UUID> = []
        var started: UUID?

        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: false,
            lingeringIds: &lingering,
            startLinger: { started = $0 }
        )

        #expect(started == item.id)
        #expect(lingering.isEmpty, "the caller owns inserting/removing ids during the timed fade")
    }

    @Test func toggleDoesNotLingerWhenCompletedRowsAreVisible() async throws {
        let store = try await makeStore()
        let item = Item(type: .task, title: "Visible done", listId: ItemList.inboxId)
        try await store.add(item)
        var lingering: Set<UUID> = [item.id]
        var started: UUID?

        ItemCompletionLinger.toggle(
            item,
            store: store,
            showCompleted: true,
            lingeringIds: &lingering,
            startLinger: { started = $0 }
        )

        #expect(started == nil)
        #expect(!lingering.contains(item.id))
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
        var started: UUID?

        ItemCompletionLinger.incrementHabit(
            habit,
            store: store,
            showCompleted: false,
            startLinger: { started = $0 }
        )

        #expect(started == habit.id)
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
        var started: UUID?

        ItemCompletionLinger.incrementHabit(
            habit,
            store: store,
            showCompleted: true,
            startLinger: { started = $0 }
        )

        #expect(started == nil)
    }
}
