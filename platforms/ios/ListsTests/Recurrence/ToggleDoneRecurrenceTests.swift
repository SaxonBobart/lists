import XCTest
@testable import Lists

/// TASK-1 + REM-1: completing a recurring *task* spawns the next dated
/// occurrence (which re-arms its reminder via the normal add path). Habits and
/// non-recurring tasks never spawn.
@MainActor
final class ToggleDoneRecurrenceTests: XCTestCase {

    private func emptyStore() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecur-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        return store
    }

    private let due = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14

    func testCompletingMonthlyTaskSpawnsNextOccurrence() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "Pay rent", listId: ItemList.inboxId,
                        due: due, recurrence: Recurrence(rrule: "FREQ=MONTHLY"))
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id)

        XCTAssertEqual(store.items.count, before + 1, "completing a recurring task spawns the next one")
        let original = try XCTUnwrap(store.items.first { $0.id == task.id })
        XCTAssertTrue(original.done)
        let spawned = try XCTUnwrap(store.items.first { $0.id != task.id && $0.title == "Pay rent" })
        XCTAssertFalse(spawned.done)
        XCTAssertNil(spawned.completedAt)
        XCTAssertGreaterThan(spawned.due ?? .distantPast, due, "next due is advanced")
    }

    func testCompletingNonRecurringTaskSpawnsNothing() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "One-off", listId: ItemList.inboxId, due: due)
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id)

        XCTAssertEqual(store.items.count, before)
    }

    func testCompletingExpiredRecurrenceSpawnsNothing() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "Expired", listId: ItemList.inboxId,
                        due: due, recurrence: Recurrence(rrule: "FREQ=MONTHLY;UNTIL=20200101T000000Z"))
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id)

        XCTAssertEqual(store.items.count, before, "a series past its UNTIL ends quietly")
    }

    func testUncompletingNeverSpawns() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "Already done", listId: ItemList.inboxId,
                        done: true, due: due, recurrence: Recurrence(rrule: "FREQ=DAILY"))
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id) // done -> not done

        XCTAssertEqual(store.items.count, before, "only the false→true transition spawns")
    }

    func testRecurringTaskWithNoDueDateSpawnsNothing() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "No anchor", listId: ItemList.inboxId,
                        recurrence: Recurrence(rrule: "FREQ=DAILY"))
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id)

        XCTAssertEqual(store.items.count, before, "no due date = no anchor to advance from")
    }
}
