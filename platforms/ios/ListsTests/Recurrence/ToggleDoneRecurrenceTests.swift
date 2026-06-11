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

    /// REC-1: a recurring task advances in its stored `dueTimeZone`, not the
    /// device zone. Monthly from Feb 15 09:00 New York must stay on the 15th
    /// at 09:00 *in New York* — a device-zone (UTC) computation would shift
    /// the wall-clock hour across a DST boundary. (The spawned month is
    /// whatever the REC-6 roll-forward lands on, so only day/time are pinned.)
    func testRecurringTaskAdvancesInItsStoredTimeZone() async throws {
        let store = try await emptyStore()
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let dueNY = ny.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 9, minute: 0))!
        let task = Item(type: .task, title: "Monthly NY", listId: ItemList.inboxId,
                        due: dueNY, dueTimeZone: "America/New_York",
                        recurrence: Recurrence(rrule: "FREQ=MONTHLY"))
        try await store.add(task)

        try await store.toggleDone(task.id)

        let spawned = try XCTUnwrap(store.items.first { $0.id != task.id && $0.title == "Monthly NY" })
        let due = try XCTUnwrap(spawned.due)
        let comps = ny.dateComponents([.day, .hour, .minute], from: due)
        XCTAssertEqual(comps.day, 15, "same day-of-month in the task's own zone")
        XCTAssertEqual(comps.hour, 9, "wall-clock hour preserved in the task's own zone across DST")
        XCTAssertEqual(comps.minute, 0)
    }

    /// REC-6: completing a task that has been overdue for weeks must spawn a
    /// successor in the *future* (anchored to the original cadence), not a
    /// successor that is itself already overdue with no reminder.
    func testOverdueRecurringTaskSpawnsSuccessorInTheFuture() async throws {
        let store = try await emptyStore()
        let cal = Calendar.current
        let staleDue = cal.date(byAdding: .day, value: -30, to: .now)!
        let task = Item(type: .task, title: "Water plants", listId: ItemList.inboxId,
                        due: staleDue, recurrence: Recurrence(rrule: "FREQ=DAILY"))
        try await store.add(task)

        try await store.toggleDone(task.id)

        let spawned = try XCTUnwrap(store.items.first { $0.id != task.id && $0.title == "Water plants" })
        let due = try XCTUnwrap(spawned.due)
        XCTAssertGreaterThan(due, .now, "the successor lands in the future, not 29 days ago")
        XCTAssertEqual(cal.component(.hour, from: due), cal.component(.hour, from: staleDue),
                       "roll-forward keeps the original time of day")
        XCTAssertEqual(cal.component(.minute, from: due), cal.component(.minute, from: staleDue))
    }

    /// REC-2: tick → untick → tick must leave exactly ONE open successor, not
    /// a duplicate per completion.
    func testUntickRetickSpawnsOnlyOneSuccessor() async throws {
        let store = try await emptyStore()
        let due = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let task = Item(type: .task, title: "Take out bins", listId: ItemList.inboxId,
                        due: due, recurrence: Recurrence(rrule: "FREQ=DAILY"))
        try await store.add(task)

        try await store.toggleDone(task.id)   // tick: spawns the successor
        try await store.toggleDone(task.id)   // untick (mis-tap corrected)
        try await store.toggleDone(task.id)   // tick again

        let successors = store.items.filter { $0.id != task.id && $0.title == "Take out bins" }
        XCTAssertEqual(successors.count, 1, "re-completing must not duplicate the spawned occurrence")
    }

    // MARK: - Events

    func testToggleDoneIsANoOpForNonCompletableEvents() async throws {
        let store = try await emptyStore()
        let event = Item(type: .event, title: "Standup", listId: ItemList.inboxId, due: due)
        try await store.add(event)

        try await store.toggleDone(event.id)

        let live = try XCTUnwrap(store.items.first { $0.id == event.id })
        XCTAssertFalse(live.done, "a non-completable event has no done state to toggle")
    }

    func testCompletingRecurringCompletableEventPreservesDuration() async throws {
        let store = try await emptyStore()
        let start = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let event = Item(type: .event, title: "Gym slot", listId: ItemList.inboxId,
                         due: start, end: start.addingTimeInterval(3_600), completable: true,
                         recurrence: Recurrence(rrule: "FREQ=WEEKLY"))
        try await store.add(event)

        try await store.toggleDone(event.id)

        let spawned = try XCTUnwrap(store.items.first { $0.id != event.id && $0.title == "Gym slot" })
        let nextStart = try XCTUnwrap(spawned.due)
        let nextEnd = try XCTUnwrap(spawned.end)
        XCTAssertEqual(nextEnd.timeIntervalSince(nextStart), 3_600, accuracy: 1,
                       "the one-hour span advances with its duration intact")
        XCTAssertFalse(spawned.done)
    }
}
