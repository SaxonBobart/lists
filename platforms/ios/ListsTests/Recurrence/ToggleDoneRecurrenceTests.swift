import Foundation
import Testing
@testable import Lists

/// Recurring work keeps one durable document. Completion records one genuine
/// occurrence, accounts for crossed cadence slots as missed, and advances the
/// same item to its next due date.
@MainActor
struct ToggleDoneRecurrenceTests {

    private struct NoopNotificationScheduler: NotificationScheduling {
        func schedule(_ item: Item) async {}
        func cancel(_ id: UUID) async {}
    }

    private func emptyStore(root: URL? = nil) async throws -> ItemStore {
        let root = root ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecur-\(UUID().uuidString)")
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
        try await store.bootstrap()
        return store
    }

    @Test func completingRecurringTaskAdvancesSameDocument() async throws {
        let store = try await emptyStore()
        let due = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let task = Item(
            type: .task,
            title: "Pay rent",
            body: "Account details stay here.",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=MONTHLY")
        )
        try await store.add(task)

        try await store.toggleDone(task.id)

        #expect(store.items.filter { $0.title == task.title }.count == 1)
        let advanced = try #require(store.item(task.id))
        #expect(!advanced.done)
        #expect(advanced.completedAt == nil)
        #expect(advanced.body == task.body)
        #expect(try #require(advanced.due) > due)
        #expect(advanced.recurrenceOccurrences.map(\.status) == [.completed, .open])
        #expect(advanced.recurrenceSourceId == nil)
        #expect(advanced.recurrenceSuccessorId == nil)
    }

    @Test func occurrenceLedgerSurvivesColdReloadWithoutAnotherFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecurCold-\(UUID().uuidString)")
        let store = try await emptyStore(root: root)
        let due = try #require(Calendar.current.date(byAdding: .hour, value: 1, to: .now))
        let task = Item(
            type: .task,
            title: "One file forever",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        try await store.add(task)
        try await store.toggleDone(task.id)
        let warm = try #require(store.item(task.id))

        let restarted = try await emptyStore(root: root)
        let cold = try #require(restarted.item(task.id))

        #expect(restarted.items.filter { $0.title == task.title }.count == 1)
        #expect(cold.recurrenceOccurrences.map(\.id) == warm.recurrenceOccurrences.map(\.id))
        #expect(cold.recurrenceOccurrences.map(\.status) == warm.recurrenceOccurrences.map(\.status))
        #expect(zip(cold.recurrenceOccurrences, warm.recurrenceOccurrences).allSatisfy { pair in
            abs(pair.0.scheduledAt.timeIntervalSince(pair.1.scheduledAt)) < 0.001
                && (pair.0.completedAt == nil && pair.1.completedAt == nil
                    || abs((pair.0.completedAt ?? .distantPast).timeIntervalSince(
                        pair.1.completedAt ?? .distantPast
                    )) < 0.001)
        })
        #expect(abs(try #require(cold.due).timeIntervalSince(try #require(warm.due))) < 0.001)
    }

    @Test func overdueTaskAccountsForMissesThenCompletesOnlyCurrentOccurrence() async throws {
        let store = try await emptyStore()
        let staleDue = try #require(Calendar.current.date(byAdding: .day, value: -3, to: .now))
        let task = Item(
            type: .task,
            title: "Take medication",
            listId: ItemList.inboxId,
            due: staleDue,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        try await store.add(task)

        try await store.toggleDone(task.id)

        let advanced = try #require(store.item(task.id))
        #expect(advanced.recurrenceOccurrences.filter { $0.status == .missed }.count >= 2)
        #expect(advanced.recurrenceOccurrences.filter { $0.status == .completed }.count == 1)
        #expect(advanced.recurrenceOccurrences.filter { $0.status == .open }.count == 1)
        #expect(advanced.recurrenceOccurrences.filter {
            $0.status == .missed && $0.completedAt != nil
        }.isEmpty)
        #expect(try #require(advanced.due) > .now)
    }

    @Test func completingExpiredSeriesEndsSameItem() async throws {
        let store = try await emptyStore()
        let due = try #require(Calendar.current.date(byAdding: .hour, value: -1, to: .now))
        let until = ScheduleFormatting.formatUntil(due)
        let task = Item(
            type: .task,
            title: "Last occurrence",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY;UNTIL=\(until)")
        )
        try await store.add(task)

        try await store.toggleDone(task.id)

        let ended = try #require(store.item(task.id))
        #expect(store.items.filter { $0.title == task.title }.count == 1)
        #expect(ended.done)
        #expect(ended.completedAt != nil)
        #expect(ended.recurrenceOccurrences.map(\.status) == [.completed])
    }

    @Test func uncompletingEndedSeriesCorrectsHistoryToMissedWithoutRewinding() async throws {
        let store = try await emptyStore()
        let due = try #require(Calendar.current.date(byAdding: .hour, value: -1, to: .now))
        let until = ScheduleFormatting.formatUntil(due)
        let task = Item(
            type: .task,
            title: "Correct me",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY;UNTIL=\(until)")
        )
        try await store.add(task)
        try await store.toggleDone(task.id)
        let endedDue = store.item(task.id)?.due

        try await store.toggleDone(task.id)

        let corrected = try #require(store.item(task.id))
        #expect(!corrected.done)
        #expect(corrected.completedAt == nil)
        #expect(corrected.due == endedDue)
        #expect(corrected.recurrenceOccurrences.map(\.status) == [.missed])
    }

    @Test func recurringCompletableEventPreservesDurationInPlace() async throws {
        let store = try await emptyStore()
        let start = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let event = Item(
            type: .event,
            title: "Gym slot",
            listId: ItemList.inboxId,
            due: start,
            end: start.addingTimeInterval(3_600),
            completable: true,
            recurrence: Recurrence(rrule: "FREQ=WEEKLY")
        )
        try await store.add(event)

        try await store.toggleDone(event.id)

        let advanced = try #require(store.item(event.id))
        #expect(store.items.filter { $0.title == event.title }.count == 1)
        let nextStart = try #require(advanced.due)
        let nextEnd = try #require(advanced.end)
        #expect(abs(nextEnd.timeIntervalSince(nextStart) - 3_600) <= 1)
        #expect(!advanced.done)
    }

    @Test func nonRecurringTaskStillUsesOrdinaryCompletion() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "One-off", listId: ItemList.inboxId)
        try await store.add(task)

        try await store.toggleDone(task.id)

        let completed = try #require(store.item(task.id))
        #expect(completed.done)
        #expect(completed.completedAt != nil)
        #expect(completed.recurrenceOccurrences.isEmpty)
    }

    @Test func nonCompletableEventStillCannotBeChecked() async throws {
        let store = try await emptyStore()
        let event = Item(type: .event, title: "Standup", listId: ItemList.inboxId, due: .now)
        try await store.add(event)

        try await store.toggleDone(event.id)

        #expect(store.item(event.id)?.done == false)
    }
}
