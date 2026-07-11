import Foundation
import Testing
@testable import Lists

/// Completing a recurring *task* spawns the next dated occurrence, which
/// re-arms its reminder via the normal add path. Habits and non-recurring
/// tasks never spawn.
@MainActor
struct ToggleDoneRecurrenceTests {

    private struct NoopNotificationScheduler: NotificationScheduling {
        func schedule(_ item: Item) async {}
        func cancel(_ id: UUID) async {}
    }

    private enum SimulatedRecurrenceInterruption: Error {
        case afterSuccessorCommit
        case beforeRootCommit
    }

    @MainActor
    private final class OneShotInterruption {
        private var shouldInterrupt = true

        func interrupt() throws {
            guard shouldInterrupt else { return }
            shouldInterrupt = false
            throw SimulatedRecurrenceInterruption.afterSuccessorCommit
        }
    }

    private func emptyStore() async throws -> ItemStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecur-\(UUID().uuidString)")
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
        try await store.bootstrap()
        return store
    }

    private let due = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14

    @Test func completingMonthlyTaskSpawnsNextOccurrence() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "Pay rent", listId: ItemList.inboxId,
                        due: due, recurrence: Recurrence(rrule: "FREQ=MONTHLY"))
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id)

        #expect(store.items.count == before + 1, "completing a recurring task spawns the next one")
        let original = try #require(store.items.first { $0.id == task.id })
        #expect(original.done)
        let spawned = try #require(store.items.first { $0.id != task.id && $0.title == "Pay rent" })
        #expect(!spawned.done)
        #expect(spawned.completedAt == nil)
        let spawnedDue = try #require(spawned.due)
        #expect(spawnedDue > due, "next due is advanced")
    }

    @Test func interruptedCompletionLeavesAnOpenRetryableSeries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecurInterrupted-\(UUID().uuidString)")
        let interruption = OneShotInterruption()
        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                recurringSuccessorCommitted: { try interruption.interrupt() }
            )
        )
        try await store.bootstrap()
        let due = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let task = Item(
            type: .task,
            title: "Durable recurring series",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        try await store.add(task)

        do {
            try await store.toggleDone(task.id)
            Issue.record("the injected interruption must fail completion")
        } catch is SimulatedRecurrenceInterruption {}

        let interruptedSeries = store.items.filter { $0.title == task.title }
        #expect(interruptedSeries.first { $0.id == task.id }?.done == false)
        #expect(interruptedSeries.filter { $0.id != task.id && !$0.done }.count == 1)
        var pendingSuccessor = try #require(interruptedSeries.first { $0.id != task.id })
        #expect(pendingSuccessor.recurrenceSourceId == task.id)
        #expect(interruptedSeries.first { $0.id == task.id }?.recurrenceSuccessorId == nil)
        let interruptedCold = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).filter { $0.title == task.title }
        #expect(interruptedCold.first { $0.id == task.id }?.done == false)
        #expect(interruptedCold.filter { $0.id != task.id && !$0.done }.count == 1)
        let coldPending = try #require(interruptedCold.first { $0.id == pendingSuccessor.id })
        #expect(coldPending.recurrenceSourceId == task.id)
        #expect(interruptedCold.first { $0.id == task.id }?.recurrenceSuccessorId == nil)

        let restarted = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
        try await restarted.bootstrap()
        pendingSuccessor = try #require(restarted.item(pendingSuccessor.id))
        #expect(restarted.item(task.id)?.recurrenceSuccessorId == nil)

        // Make date-only matching impossible. The retry must find the durable
        // lineage record, reuse this id, and roll the edited source cadence
        // back into the future.
        var editedSource = try #require(restarted.item(task.id))
        editedSource.due = Calendar.current.date(
            byAdding: .day,
            value: -30,
            to: .now
        )
        try await restarted.update(editedSource)
        try await restarted.toggleDone(task.id)

        let retriedSeries = restarted.items.filter { $0.title == task.title }
        #expect(retriedSeries.first { $0.id == task.id }?.done == true)
        #expect(retriedSeries.filter { $0.id != task.id && !$0.done }.count == 1)
        let retriedSuccessor = try #require(retriedSeries.first { $0.id != task.id })
        #expect(retriedSuccessor.id == pendingSuccessor.id)
        #expect(retriedSuccessor.recurrenceSourceId == task.id)
        #expect(retriedSeries.first { $0.id == task.id }?.recurrenceSuccessorId == pendingSuccessor.id)
        #expect(try #require(retriedSuccessor.due) > .now)
        let retriedCold = try await FileStore(root: root).loadAll()
            .lists.flatMap(\.items).filter { $0.title == task.title }
        #expect(retriedCold.first { $0.id == task.id }?.done == true)
        #expect(retriedCold.filter { $0.id != task.id && !$0.done }.count == 1)
        let coldSuccessor = try #require(retriedCold.first { $0.id == pendingSuccessor.id })
        #expect(coldSuccessor.recurrenceSourceId == task.id)
        #expect(retriedCold.first { $0.id == task.id }?.recurrenceSuccessorId == pendingSuccessor.id)
    }

    @Test func interruptionBeforeRootCommitKeepsSuccessorPendingForRestartedRetry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecurRootInterrupted-\(UUID().uuidString)")
        let firstStore = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                recurringRootWillCommit: {
                    throw SimulatedRecurrenceInterruption.beforeRootCommit
                }
            )
        )
        try await firstStore.bootstrap()
        let due = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let task = Item(
            type: .task,
            title: "Root-last recurring series",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        try await firstStore.add(task)

        do {
            try await firstStore.toggleDone(task.id)
            Issue.record("the injected root interruption must fail completion")
        } catch is SimulatedRecurrenceInterruption {}

        let interruptedCold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        #expect(interruptedCold.first { $0.id == task.id }?.done == false)
        let pending = try #require(interruptedCold.first {
            $0.recurrenceSourceId == task.id
        })
        #expect(interruptedCold.first { $0.id == task.id }?.recurrenceSuccessorId == nil)

        let restarted = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
        try await restarted.bootstrap()
        var edited = try #require(restarted.item(task.id))
        edited.title = "Edited before retry"
        edited.body = "Current recurrence notes"
        try await restarted.update(edited)
        try await restarted.toggleDone(task.id)

        let retriedSource = try #require(restarted.item(task.id))
        let retriedSuccessor = try #require(restarted.item(pending.id))
        #expect(retriedSource.done == true)
        #expect(retriedSource.recurrenceSuccessorId == pending.id)
        #expect(retriedSource.title == edited.title)
        #expect(retriedSource.body == edited.body)
        #expect(retriedSuccessor.title == task.title)
        #expect(retriedSuccessor.body.isEmpty)
    }

    @Test func interruptedCompletionAdoptsLegacySuccessorWithoutRewritingIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsRecurLegacyLineage-\(UUID().uuidString)")
        let firstStore = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler(),
            maintenanceTestHooks: ItemStore.MaintenanceTestHooks(
                recurringRootWillCommit: {
                    throw SimulatedRecurrenceInterruption.beforeRootCommit
                }
            )
        )
        try await firstStore.bootstrap()
        let due = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let nextDue = try #require(RecurrenceEngine.nextOccurrence(
            after: due,
            rrule: "FREQ=DAILY",
            calendar: .current
        ))
        let source = Item(
            type: .task,
            title: "Legacy recurring series",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        var legacySuccessor = source
        legacySuccessor.id = UUID()
        legacySuccessor.body = "Keep future-occurrence notes"
        legacySuccessor.tags = ["customized"]
        legacySuccessor.due = nextDue
        legacySuccessor.createdAt = .now
        legacySuccessor.modifiedAt = legacySuccessor.createdAt
        try await firstStore.add(source)
        try await firstStore.add(legacySuccessor)

        do {
            try await firstStore.toggleDone(source.id)
            Issue.record("the injected root interruption must fail legacy adoption")
        } catch is SimulatedRecurrenceInterruption {}

        let interruptedCold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        #expect(interruptedCold.first { $0.id == source.id }?.done == false)
        #expect(interruptedCold.first { $0.id == source.id }?.recurrenceSuccessorId == nil)
        let interruptedLegacy = try #require(interruptedCold.first {
            $0.id == legacySuccessor.id
        })
        #expect(interruptedLegacy.recurrenceSourceId == source.id)
        #expect(interruptedLegacy.body.trimmingCharacters(in: .newlines) == legacySuccessor.body)
        #expect(interruptedLegacy.tags == legacySuccessor.tags)

        let store = ItemStore(
            store: FileStore(root: root),
            scheduler: NoopNotificationScheduler()
        )
        try await store.bootstrap()
        var movedCadence = try #require(store.item(source.id))
        movedCadence.due = Calendar.current.date(byAdding: .day, value: -30, to: .now)
        try await store.update(movedCadence)
        try await store.toggleDone(source.id)

        let series = store.items.filter { $0.title == source.title }
        #expect(series.count == 2)
        let adopted = try #require(store.item(legacySuccessor.id))
        #expect(adopted.recurrenceSourceId == source.id)
        #expect(adopted.body.trimmingCharacters(in: .newlines) == legacySuccessor.body)
        #expect(adopted.tags == legacySuccessor.tags)
        #expect(store.item(source.id)?.recurrenceSuccessorId == legacySuccessor.id)
        let cold = try await FileStore(root: root).loadAll().lists.flatMap(\.items)
        let coldAdopted = try #require(cold.first { $0.id == legacySuccessor.id })
        #expect(coldAdopted.recurrenceSourceId == source.id)
        #expect(coldAdopted.body.trimmingCharacters(in: .newlines) == legacySuccessor.body)
        #expect(coldAdopted.tags == legacySuccessor.tags)
        #expect(cold.first { $0.id == source.id }?.recurrenceSuccessorId == legacySuccessor.id)
    }

    @Test func identicalIndependentSeriesKeepSeparateSuccessors() async throws {
        let store = try await emptyStore()
        let due = Calendar.current.date(byAdding: .day, value: 1, to: .now)
        let first = Item(
            type: .task,
            title: "Same visible recurrence",
            listId: ItemList.inboxId,
            due: due,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        let second = Item(
            type: .task,
            title: first.title,
            listId: first.listId,
            due: due,
            recurrence: first.recurrence
        )
        try await store.add(first)
        try await store.add(second)

        try await store.toggleDone(first.id)
        try await store.toggleDone(second.id)

        let firstSuccessor = try #require(store.items.first {
            $0.recurrenceSourceId == first.id
        })
        let secondSuccessor = try #require(store.items.first {
            $0.recurrenceSourceId == second.id
        })
        #expect(firstSuccessor.id != secondSuccessor.id)
        #expect(store.item(first.id)?.recurrenceSuccessorId == firstSuccessor.id)
        #expect(store.item(second.id)?.recurrenceSuccessorId == secondSuccessor.id)
    }

    @Test func legacyMatchingDoesNotAdoptAnUntickedSeriesRoot() async throws {
        let store = try await emptyStore()
        let firstDue = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let secondDue = try #require(RecurrenceEngine.nextOccurrence(
            after: firstDue,
            rrule: "FREQ=DAILY",
            calendar: .current
        ))
        let untickedRoot = Item(
            type: .task,
            title: "Matching independent roots",
            listId: ItemList.inboxId,
            due: secondDue,
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )
        let otherSource = Item(
            type: .task,
            title: untickedRoot.title,
            listId: untickedRoot.listId,
            due: firstDue,
            recurrence: untickedRoot.recurrence
        )
        try await store.add(untickedRoot)
        try await store.toggleDone(untickedRoot.id)
        try await store.toggleDone(untickedRoot.id)
        let untickedRootLink = try #require(store.item(untickedRoot.id)?.recurrenceSuccessorId)

        try await store.add(otherSource)
        try await store.toggleDone(otherSource.id)

        let otherLink = try #require(store.item(otherSource.id)?.recurrenceSuccessorId)
        #expect(otherLink != untickedRoot.id)
        #expect(otherLink != untickedRootLink)
        #expect(store.item(untickedRoot.id)?.recurrenceSourceId == nil)
        #expect(store.item(untickedRoot.id)?.recurrenceSuccessorId == untickedRootLink)
        #expect(store.item(otherLink)?.recurrenceSourceId == otherSource.id)
    }

    @Test func completingNonRecurringTaskSpawnsNothing() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "One-off", listId: ItemList.inboxId, due: due)
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id)

        #expect(store.items.count == before)
    }

    @Test func completingExpiredRecurrenceSpawnsNothing() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "Expired", listId: ItemList.inboxId,
                        due: due, recurrence: Recurrence(rrule: "FREQ=MONTHLY;UNTIL=20200101T000000Z"))
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id)

        #expect(store.items.count == before, "a series past its UNTIL ends quietly")
    }

    @Test func uncompletingNeverSpawns() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "Already done", listId: ItemList.inboxId,
                        done: true, due: due, recurrence: Recurrence(rrule: "FREQ=DAILY"))
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id) // done -> not done

        #expect(store.items.count == before, "only the false→true transition spawns")
    }

    @Test func recurringTaskWithNoDueDateSpawnsNothing() async throws {
        let store = try await emptyStore()
        let task = Item(type: .task, title: "No anchor", listId: ItemList.inboxId,
                        recurrence: Recurrence(rrule: "FREQ=DAILY"))
        try await store.add(task)
        let before = store.items.count

        try await store.toggleDone(task.id)

        #expect(store.items.count == before, "no due date = no anchor to advance from")
    }

    /// A recurring task advances in its stored `dueTimeZone`, not the device
    /// zone. Monthly from Feb 15 09:00 New York must stay on the 15th at 09:00
    /// *in New York*; a device-zone (UTC) computation would shift the
    /// wall-clock hour across a DST boundary. The spawned month is whatever
    /// the roll-forward lands on, so only day/time are pinned.
    @Test func recurringTaskAdvancesInItsStoredTimeZone() async throws {
        let store = try await emptyStore()
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let dueNY = ny.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 9, minute: 0))!
        let task = Item(type: .task, title: "Monthly NY", listId: ItemList.inboxId,
                        due: dueNY, dueTimeZone: "America/New_York",
                        recurrence: Recurrence(rrule: "FREQ=MONTHLY"))
        try await store.add(task)

        try await store.toggleDone(task.id)

        let spawned = try #require(store.items.first { $0.id != task.id && $0.title == "Monthly NY" })
        let due = try #require(spawned.due)
        let comps = ny.dateComponents([.day, .hour, .minute], from: due)
        #expect(comps.day == 15, "same day-of-month in the task's own zone")
        #expect(comps.hour == 9, "wall-clock hour preserved in the task's own zone across DST")
        #expect(comps.minute == 0)
    }

    /// Completing a task that has been overdue for weeks must spawn a successor
    /// in the *future* (anchored to the original cadence), not a successor that
    /// is itself already overdue with no reminder.
    @Test func overdueRecurringTaskSpawnsSuccessorInTheFuture() async throws {
        let store = try await emptyStore()
        let cal = Calendar.current
        let staleDue = cal.date(byAdding: .day, value: -30, to: .now)!
        let task = Item(type: .task, title: "Water plants", listId: ItemList.inboxId,
                        due: staleDue, recurrence: Recurrence(rrule: "FREQ=DAILY"))
        try await store.add(task)

        try await store.toggleDone(task.id)

        let spawned = try #require(store.items.first { $0.id != task.id && $0.title == "Water plants" })
        let due = try #require(spawned.due)
        #expect(due > .now, "the successor lands in the future, not 29 days ago")
        #expect(
            cal.component(.hour, from: due) == cal.component(.hour, from: staleDue),
            "roll-forward keeps the original time of day"
        )
        #expect(cal.component(.minute, from: due) == cal.component(.minute, from: staleDue))
    }

    /// Tick -> untick -> tick must leave exactly one open successor, not a
    /// duplicate per completion.
    @Test func untickRetickSpawnsOnlyOneSuccessor() async throws {
        let store = try await emptyStore()
        let due = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let task = Item(type: .task, title: "Take out bins", listId: ItemList.inboxId,
                        due: due, recurrence: Recurrence(rrule: "FREQ=DAILY"))
        try await store.add(task)

        try await store.toggleDone(task.id)   // tick: spawns the successor
        var customized = try #require(store.items.first {
            $0.recurrenceSourceId == task.id
        })
        customized.body = "Future occurrence notes"
        customized.tags = ["future"]
        try await store.update(customized)
        try await store.toggleDone(task.id)   // untick (mis-tap corrected)
        try await store.toggleDone(task.id)   // tick again

        let successors = store.items.filter { $0.id != task.id && $0.title == "Take out bins" }
        #expect(successors.count == 1, "re-completing must not duplicate the spawned occurrence")
        #expect(successors.first?.id == customized.id)
        #expect(successors.first?.body == customized.body)
        #expect(successors.first?.tags == customized.tags)
        #expect(store.item(task.id)?.recurrenceSuccessorId == customized.id)
    }

    // MARK: - Events

    @Test func toggleDoneIsANoOpForNonCompletableEvents() async throws {
        let store = try await emptyStore()
        let event = Item(type: .event, title: "Standup", listId: ItemList.inboxId, due: due)
        try await store.add(event)

        try await store.toggleDone(event.id)

        let live = try #require(store.items.first { $0.id == event.id })
        #expect(!live.done, "a non-completable event has no done state to toggle")
    }

    @Test func completingRecurringCompletableEventPreservesDuration() async throws {
        let store = try await emptyStore()
        let start = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let event = Item(type: .event, title: "Gym slot", listId: ItemList.inboxId,
                         due: start, end: start.addingTimeInterval(3_600), completable: true,
                         recurrence: Recurrence(rrule: "FREQ=WEEKLY"))
        try await store.add(event)

        try await store.toggleDone(event.id)

        let spawned = try #require(store.items.first { $0.id != event.id && $0.title == "Gym slot" })
        let nextStart = try #require(spawned.due)
        let nextEnd = try #require(spawned.end)
        #expect(
            abs(nextEnd.timeIntervalSince(nextStart) - 3_600) <= 1,
            "the one-hour span advances with its duration intact"
        )
        #expect(!spawned.done)
    }

    @Test func untickRetickRecurringCompletableEventSpawnsOnlyOneSuccessor() async throws {
        let store = try await emptyStore()
        let start = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let event = Item(type: .event, title: "Gym slot", listId: ItemList.inboxId,
                         due: start, end: start.addingTimeInterval(3_600), completable: true,
                         recurrence: Recurrence(rrule: "FREQ=WEEKLY"))
        try await store.add(event)

        try await store.toggleDone(event.id)
        try await store.toggleDone(event.id)
        try await store.toggleDone(event.id)

        let successors = store.items.filter { $0.id != event.id && $0.title == "Gym slot" }
        #expect(successors.count == 1, "re-completing a recurring event must not duplicate its successor")
        #expect(successors.first?.type == .event)
    }
}
