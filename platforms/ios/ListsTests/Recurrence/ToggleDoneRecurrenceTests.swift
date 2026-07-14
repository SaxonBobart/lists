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

    @Test func historyCorrectionPersistsWithoutChangingCurrentOccurrence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecurCorrection-\(UUID().uuidString)")
        let store = try await emptyStore(root: root)
        let now = Date.now
        let missedDate = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let currentDate = try #require(Calendar.current.date(byAdding: .day, value: 1, to: now))
        let correctionDate = missedDate.addingTimeInterval(3_600)
        let missed = RecurrenceOccurrence(
            scheduledAt: missedDate,
            status: .missed
        )
        let current = RecurrenceOccurrence(
            scheduledAt: currentDate,
            status: .open
        )
        let task = Item(
            type: .task,
            title: "Daily review",
            listId: ItemList.inboxId,
            due: currentDate,
            recurrence: Recurrence(rrule: "FREQ=DAILY"),
            recurrenceOccurrences: [missed, current]
        )
        try await store.add(task)

        try await store.correctRecurrenceOccurrence(
            task.id,
            occurrenceId: missed.id,
            status: .completed,
            completedAt: correctionDate
        )

        let corrected = try #require(store.item(task.id))
        #expect(corrected.due == currentDate)
        #expect(corrected.recurrence?.rrule == "FREQ=DAILY")
        #expect(corrected.done == false)
        #expect(corrected.completedAt == nil)
        #expect(corrected.recurrenceOccurrences.first(where: { $0.id == missed.id })?.status == .completed)
        #expect(corrected.recurrenceOccurrences.first(where: { $0.id == missed.id })?.completedAt == correctionDate)
        #expect(corrected.recurrenceOccurrences.first(where: { $0.id == current.id }) == current)

        let reloaded = try await emptyStore(root: root)
        let durable = try #require(reloaded.item(task.id))
        #expect(abs(try #require(durable.due).timeIntervalSince(currentDate)) < 0.001)
        #expect(durable.recurrenceOccurrences.first(where: { $0.id == missed.id })?.status == .completed)
        #expect(abs(try #require(
            durable.recurrenceOccurrences.first(where: { $0.id == missed.id })?.completedAt
        ).timeIntervalSince(correctionDate)) < 0.001)
        let durableCurrent = try #require(
            durable.recurrenceOccurrences.first(where: { $0.id == current.id })
        )
        #expect(durableCurrent.status == .open)
        #expect(durableCurrent.completedAt == nil)
        #expect(abs(durableCurrent.scheduledAt.timeIntervalSince(currentDate)) < 0.001)
    }

    @Test func completedHistoryCanReturnToMissedWithoutMovingSchedule() async throws {
        let store = try await emptyStore()
        let now = Date.now
        let completedDate = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let currentDate = try #require(Calendar.current.date(byAdding: .day, value: 1, to: now))
        let completion = RecurrenceOccurrence(
            scheduledAt: completedDate,
            status: .completed,
            completedAt: completedDate.addingTimeInterval(120)
        )
        let current = RecurrenceOccurrence(scheduledAt: currentDate, status: .open)
        let task = Item(
            type: .task,
            title: "Water plants",
            listId: ItemList.inboxId,
            due: currentDate,
            recurrence: Recurrence(rrule: "FREQ=WEEKLY"),
            recurrenceOccurrences: [completion, current]
        )
        try await store.add(task)

        try await store.correctRecurrenceOccurrence(
            task.id,
            occurrenceId: completion.id,
            status: .missed,
            completedAt: nil
        )

        let corrected = try #require(store.item(task.id))
        #expect(corrected.due == currentDate)
        #expect(corrected.done == false)
        #expect(corrected.recurrenceOccurrences.first(where: { $0.id == completion.id })?.status == .missed)
        #expect(corrected.recurrenceOccurrences.first(where: { $0.id == completion.id })?.completedAt == nil)
        #expect(corrected.recurrenceOccurrences.first(where: { $0.id == current.id }) == current)
    }

    @Test func terminalHistoryCorrectionKeepsOrdinaryCompletionInSync() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecurTerminalCorrection-\(UUID().uuidString)")
        let store = try await emptyStore(root: root)
        let scheduledAt = try #require(Calendar.current.date(byAdding: .hour, value: -2, to: .now))
        let originalCompletion = scheduledAt.addingTimeInterval(300)
        let occurrence = RecurrenceOccurrence(
            scheduledAt: scheduledAt,
            status: .completed,
            completedAt: originalCompletion
        )
        let task = Item(
            type: .task,
            title: "Final review",
            listId: ItemList.inboxId,
            done: true,
            completedAt: originalCompletion,
            due: scheduledAt,
            recurrence: Recurrence(rrule: "FREQ=DAILY;UNTIL=20260714"),
            recurrenceOccurrences: [occurrence]
        )
        try await store.add(task)

        try await store.correctRecurrenceOccurrence(
            task.id,
            occurrenceId: occurrence.id,
            status: .missed,
            completedAt: nil
        )
        #expect(store.item(task.id)?.done == false)
        #expect(store.item(task.id)?.completedAt == nil)
        #expect(store.item(task.id)?.recurrenceOccurrences == [
            RecurrenceOccurrence(
                id: occurrence.id,
                scheduledAt: scheduledAt,
                timeZone: occurrence.timeZone,
                status: .missed
            )
        ])

        let reloadedAfterMiss = try await emptyStore(root: root)
        #expect(reloadedAfterMiss.item(task.id)?.done == false)
        #expect(reloadedAfterMiss.item(task.id)?.recurrenceOccurrences.count == 1)
        #expect(reloadedAfterMiss.item(task.id)?.recurrenceOccurrences.first?.status == .missed)

        let correctedCompletion = scheduledAt.addingTimeInterval(900)
        try await reloadedAfterMiss.correctRecurrenceOccurrence(
            task.id,
            occurrenceId: occurrence.id,
            status: .completed,
            completedAt: correctedCompletion
        )
        #expect(reloadedAfterMiss.item(task.id)?.done == true)
        #expect(reloadedAfterMiss.item(task.id)?.completedAt == correctedCompletion)
    }

    @Test func currentOccurrenceCannotBeCorrectedAsHistory() async throws {
        let store = try await emptyStore()
        let due = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let current = RecurrenceOccurrence(scheduledAt: due, status: .open)
        let task = Item(
            type: .task,
            title: "Still current",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY"),
            recurrenceOccurrences: [current]
        )
        try await store.add(task)

        await #expect(throws: ItemStore.RecurrenceHistoryError.currentOccurrenceCannotBeCorrected) {
            try await store.correctRecurrenceOccurrence(
                task.id,
                occurrenceId: current.id,
                status: .completed,
                completedAt: .now
            )
        }
    }
}
