import Foundation
import Testing
@testable import Lists

/// The Log screen edits individual completion events. These pin the store methods
/// behind it (add / delete / retime / −1), and that each keeps memory and disk in
/// sync by persisting before publishing the new in-memory value.
@MainActor
struct HabitCompletionStoreTests {
    private actor RecordingNotificationScheduler: NotificationScheduling {
        private var acknowledgedItemIds: [UUID] = []

        func schedule(_ item: Item) async {}
        func cancel(_ id: UUID) async {}

        func acknowledgeDelivered(_ id: UUID) async {
            acknowledgedItemIds.append(id)
        }

        func acknowledgements() -> [UUID] {
            acknowledgedItemIds
        }
    }

    private func storeWithHabit(
        frequency: HabitFrequency = .daily,
        goal: Int = 5,
        scheduler: any NotificationScheduling = NotificationScheduler.shared,
        reminder: Bool = false
    ) async throws -> (store: ItemStore, root: URL, id: UUID, fileURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsHC-\(UUID().uuidString)")
        let fileStore = FileStore(root: root)
        let store = ItemStore(store: fileStore, scheduler: scheduler)
        try await store.bootstrap()
        let habit = Item(
            type: .habit,
            title: "Water",
            listId: ItemList.inboxId,
            due: reminder ? ReminderPreferences.defaultTime() : nil,
            reminder: reminder ? Reminder(enabled: true) : nil,
            frequency: frequency,
            goalPerCycle: goal
        )
        try await store.add(habit)
        let inboxDirectory = try await fileStore.listDirectory(for: ItemList.inboxId)
        let fileURL = inboxDirectory.appendingPathComponent("\(habit.id.uuidString).md")
        return (store, root, habit.id, fileURL)
    }

    private func reload(_ root: URL, _ id: UUID) async throws -> Item? {
        try await FileStore(root: root).loadAll().lists.flatMap(\.items).first { $0.id == id }
    }

    /// Force exactly one write to fail without changing the stored bytes that a
    /// cold reload observes after the attempt.
    private func expectWriteFailure(
        at fileURL: URL,
        operation: () async throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let originalBytes = try Data(contentsOf: fileURL)
        try fileManager.removeItem(at: fileURL)
        try fileManager.createDirectory(at: fileURL, withIntermediateDirectories: false)

        await #expect(throws: (any Error).self) {
            try await operation()
        }

        try fileManager.removeItem(at: fileURL)
        try originalBytes.write(to: fileURL, options: .atomic)
    }

    @Test func inlineHabitDefaultsToDailyGoalAndPersists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListsInlineHabit-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()

        let id = store.addInlineItem(type: .habit, listId: ItemList.inboxId, section: nil)
        try await store.flushPendingWrites()

        let live = try #require(store.item(id))
        #expect(live.type == .habit)
        #expect(live.frequency == .daily)
        #expect(live.goalPerCycle == 1)

        let reloaded = try await reload(root, id)
        #expect(reloaded?.type == .habit)
        #expect(reloaded?.frequency == .daily)
        #expect(reloaded?.goalPerCycle == 1)
    }

    @Test func addCompletionAppendsEventAndPersists() async throws {
        let (store, root, id, _) = try await storeWithHabit()
        try await store.addCompletion(id, at: .now)
        #expect(store.item(id)?.completions.count == 1)
        let reloaded = try await reload(root, id)
        #expect(reloaded?.completions.count == 1, "in-memory add must match disk")
    }

    @Test func deleteCompletionRemovesByItsId() async throws {
        let (store, _, id, _) = try await storeWithHabit()
        try await store.addCompletion(id, at: .now)
        let cid = try #require(store.item(id)?.completions.first?.id)
        try await store.deleteCompletion(id, completionId: cid)
        #expect(store.item(id)?.completions.count == 0)
    }

    @Test func updateCompletionRetimesTheEvent() async throws {
        let (store, _, id, _) = try await storeWithHabit()
        let t0 = ISO8601.date(from: "2026-05-20T09:00:00.000Z")!
        try await store.addCompletion(id, at: t0)
        let cid = try #require(store.item(id)?.completions.first?.id)

        let t1 = ISO8601.date(from: "2026-05-18T15:30:00.000Z")!
        try await store.updateCompletion(id, completionId: cid, to: t1)
        #expect(store.item(id)?.completions.first?.at == t1)
    }

    @Test func removeLatestCompletionDropsTheMostRecentInThatCycle() async throws {
        let (store, _, id, _) = try await storeWithHabit()
        let early = ISO8601.date(from: "2026-05-20T08:00:00.000Z")!
        let late = ISO8601.date(from: "2026-05-20T20:00:00.000Z")!
        try await store.addCompletion(id, at: early)
        try await store.addCompletion(id, at: late)

        try await store.removeLatestCompletion(in: late, for: id)
        let comps = try #require(store.item(id)?.completions)
        #expect(comps.count == 1)
        #expect(comps.first?.at == early, "the −1 removes the latest event in the cycle")
    }

    @Test func incrementHabitAddsAnEventAndCapsAtGoal() async throws {
        let (store, _, id, _) = try await storeWithHabit(goal: 2)
        try await store.incrementHabit(id)
        try await store.incrementHabit(id)
        try await store.incrementHabit(id)  // already at goal → no-op
        #expect(store.item(id)?.completions.count == 2)
    }

    @Test func currentCycleCompletionAcknowledgesDeliveredReminder() async throws {
        let notifications = RecordingNotificationScheduler()
        let (store, _, id, _) = try await storeWithHabit(
            scheduler: notifications,
            reminder: true
        )

        try await store.incrementHabit(id, now: .now)

        let acknowledgements = await notifications.acknowledgements()
        #expect(acknowledgements == [id])
    }

    @Test func queuedCompletionUsesItsCapturedActionDateForAcknowledgement() async throws {
        let notifications = RecordingNotificationScheduler()
        let (store, _, id, _) = try await storeWithHabit(
            scheduler: notifications,
            reminder: true
        )
        let actionDate = try #require(
            ISO8601DateFormatter().date(from: "2026-05-31T23:59:59Z")
        )

        // The injected instant intentionally belongs to a different cycle
        // from wall-clock now. A second Date.now inside the queued write would
        // misclassify this durable completion and leave its alert unhandled.
        try await store.incrementHabit(id, now: actionDate)

        #expect(store.item(id)?.completions.last?.at == actionDate)
        #expect(await notifications.acknowledgements() == [id])
    }

    @Test func historicalCompletionDoesNotAcknowledgeCurrentReminder() async throws {
        let notifications = RecordingNotificationScheduler()
        let (store, _, id, _) = try await storeWithHabit(
            scheduler: notifications,
            reminder: true
        )

        try await store.addCompletion(
            id,
            at: .now.addingTimeInterval(-400 * 24 * 3_600)
        )

        let acknowledgements = await notifications.acknowledgements()
        #expect(acknowledgements.isEmpty)
    }

    @Test func failedCurrentCompletionDoesNotAcknowledgeReminder() async throws {
        let notifications = RecordingNotificationScheduler()
        let (store, _, id, fileURL) = try await storeWithHabit(
            scheduler: notifications,
            reminder: true
        )

        try await expectWriteFailure(at: fileURL) {
            try await store.incrementHabit(id, now: .now)
        }

        let acknowledgements = await notifications.acknowledgements()
        #expect(acknowledgements.isEmpty)
    }

    @Test func concurrentIncrementsRespectTheGoalCap() async throws {
        let (store, root, id, _) = try await storeWithHabit(goal: 1)
        let date = ISO8601.date(from: "2026-05-20T09:00:00.000Z")!

        async let first: Void = store.incrementHabit(id, now: date)
        async let second: Void = store.incrementHabit(id, now: date)
        _ = try await (first, second)

        let completions = try #require(store.item(id)?.completions)
        let persisted = try #require(try await reload(root, id)?.completions)
        #expect(completions.count == 1, "concurrent increments must not exceed the cycle goal")
        #expect(persisted == completions)
    }

    @Test func concurrentRemoveLatestCallsRemoveDistinctEvents() async throws {
        let (store, root, id, _) = try await storeWithHabit()
        let early = ISO8601.date(from: "2026-05-20T08:00:00.000Z")!
        let late = ISO8601.date(from: "2026-05-20T20:00:00.000Z")!
        try await store.addCompletions(id, on: [early, late])

        async let first: Void = store.removeLatestCompletion(in: late, for: id)
        async let second: Void = store.removeLatestCompletion(in: late, for: id)
        _ = try await (first, second)

        let completions = try #require(store.item(id)?.completions)
        let persisted = try #require(try await reload(root, id)?.completions)
        #expect(completions.isEmpty, "each queued decrement must derive its target from live state")
        #expect(persisted == completions)
    }

    @Test func addCompletionsBulkAddsOnePerDateInOneWrite() async throws {
        let (store, root, id, _) = try await storeWithHabit()
        let cal = Calendar(identifier: .iso8601)
        let start = ISO8601.date(from: "2026-05-16T12:00:00.000Z")!
        let dates = (0..<10).map { cal.date(byAdding: .day, value: $0, to: start)! }

        try await store.addCompletions(id, on: dates)

        #expect(store.item(id)?.completions.count == 10, "one event per date in the range")
        let reloaded = try await reload(root, id)
        #expect(reloaded?.completions.count == 10, "bulk add must persist in a single write")
    }

    @Test func addCompletionsWithNoDatesIsANoOp() async throws {
        let (store, _, id, _) = try await storeWithHabit()
        try await store.addCompletions(id, on: [])
        #expect(store.item(id)?.completions.count == 0)
    }

    @Test func failedAddCompletionLeavesSnapshotsUnchangedAndRetryAddsOnce() async throws {
        let (store, root, id, fileURL) = try await storeWithHabit()
        let date = ISO8601.date(from: "2026-05-20T09:00:00.000Z")!
        let before = try #require(store.item(id)?.completions)

        try await expectWriteFailure(at: fileURL) {
            try await store.addCompletion(id, at: date)
        }

        let afterFailure = try #require(store.item(id)?.completions)
        let coldAfterFailure = try #require(try await reload(root, id)?.completions)
        #expect(afterFailure == before)
        #expect(afterFailure == coldAfterFailure)

        try await store.addCompletion(id, at: date)

        let afterRetry = try #require(store.item(id)?.completions)
        let coldAfterRetry = try #require(try await reload(root, id)?.completions)
        #expect(afterRetry.count == 1)
        #expect(afterRetry.map(\.at) == [date])
        #expect(afterRetry == coldAfterRetry)
    }

    @Test func failedRangeAddLeavesSnapshotsUnchangedAndRetryAddsRangeOnce() async throws {
        let (store, root, id, fileURL) = try await storeWithHabit()
        let dates = [
            ISO8601.date(from: "2026-05-18T09:00:00.000Z")!,
            ISO8601.date(from: "2026-05-19T09:00:00.000Z")!,
            ISO8601.date(from: "2026-05-20T09:00:00.000Z")!
        ]
        let before = try #require(store.item(id)?.completions)

        try await expectWriteFailure(at: fileURL) {
            try await store.addCompletions(id, on: dates)
        }

        let afterFailure = try #require(store.item(id)?.completions)
        let coldAfterFailure = try #require(try await reload(root, id)?.completions)
        #expect(afterFailure == before)
        #expect(afterFailure == coldAfterFailure)

        try await store.addCompletions(id, on: dates)

        let afterRetry = try #require(store.item(id)?.completions)
        let coldAfterRetry = try #require(try await reload(root, id)?.completions)
        #expect(afterRetry.count == dates.count)
        #expect(afterRetry.map(\.at) == dates)
        #expect(afterRetry == coldAfterRetry)
    }

    @Test func failedUpdateLeavesSnapshotsUnchangedAndRetryRetimesOnce() async throws {
        let (store, root, id, fileURL) = try await storeWithHabit()
        let originalDate = ISO8601.date(from: "2026-05-20T09:00:00.000Z")!
        let updatedDate = ISO8601.date(from: "2026-05-18T15:30:00.000Z")!
        try await store.addCompletion(id, at: originalDate)
        let before = try #require(store.item(id)?.completions)
        let completionId = try #require(before.first?.id)

        try await expectWriteFailure(at: fileURL) {
            try await store.updateCompletion(id, completionId: completionId, to: updatedDate)
        }

        let afterFailure = try #require(store.item(id)?.completions)
        let coldAfterFailure = try #require(try await reload(root, id)?.completions)
        #expect(afterFailure == before)
        #expect(afterFailure == coldAfterFailure)

        try await store.updateCompletion(id, completionId: completionId, to: updatedDate)

        let afterRetry = try #require(store.item(id)?.completions)
        let coldAfterRetry = try #require(try await reload(root, id)?.completions)
        #expect(afterRetry.count == 1)
        #expect(afterRetry.first?.id == completionId)
        #expect(afterRetry.first?.at == updatedDate)
        #expect(afterRetry == coldAfterRetry)
    }

    @Test func failedDeleteLeavesSnapshotsUnchangedAndRetryDeletesOnce() async throws {
        let (store, root, id, fileURL) = try await storeWithHabit()
        let firstDate = ISO8601.date(from: "2026-05-19T09:00:00.000Z")!
        let secondDate = ISO8601.date(from: "2026-05-20T09:00:00.000Z")!
        try await store.addCompletions(id, on: [firstDate, secondDate])
        let before = try #require(store.item(id)?.completions)
        let deletedId = try #require(before.first?.id)

        try await expectWriteFailure(at: fileURL) {
            try await store.deleteCompletion(id, completionId: deletedId)
        }

        let afterFailure = try #require(store.item(id)?.completions)
        let coldAfterFailure = try #require(try await reload(root, id)?.completions)
        #expect(afterFailure == before)
        #expect(afterFailure == coldAfterFailure)

        try await store.deleteCompletion(id, completionId: deletedId)

        let afterRetry = try #require(store.item(id)?.completions)
        let coldAfterRetry = try #require(try await reload(root, id)?.completions)
        #expect(afterRetry.count == 1)
        #expect(afterRetry.first?.id != deletedId)
        #expect(afterRetry.first?.at == secondDate)
        #expect(afterRetry == coldAfterRetry)
    }
}
