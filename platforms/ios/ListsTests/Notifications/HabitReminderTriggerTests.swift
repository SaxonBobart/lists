import Foundation
import Testing
@preconcurrency import UserNotifications
@testable import Lists

/// A habit's reminder must *repeat* (`UNCalendarNotificationTrigger` keyed to
/// the habit's cadence, built off `item.due`'s time-of-day).
///
/// The schedule is built from the habit's NORMALIZED cadence (daily / weekly /
/// monthly) — the only cadences the habit UI offers. A legacy raw frequency
/// (`hourly`, `weekdays`, `custom`, …) must not drive a reminder schedule the
/// user can no longer see or edit: an old `hourly` habit pings once a day, not
/// every hour. One trigger per habit also keeps the app far away from the iOS
/// 64-pending-notification cap.
struct HabitReminderTriggerTests {
    private final class FakeNotificationCenter: UserNotificationRequestCenter, @unchecked Sendable {
        private enum AddFailure: Error { case injected }

        struct Snapshot: Sendable {
            var pendingTitles: [String: String]
            var pendingThreadIdentifiers: [String: String]
            var deliveredIdentifiers: Set<String>
            var removalCalls: [String: Int]
        }

        private var pending: [String: UNNotificationRequest]
        private var delivered: Set<String>
        private var removalCalls: [String: Int] = [:]
        private var removalTargets: Set<String> = []
        private var settlementQueriesRemaining: Int
        private var addFailuresRemaining = 0
        private var deliversNextAddedRequest = false
        private var deliversAddedOnPendingQuery = false
        private var deliversRemovedRequests = false
        private var lastAddedIdentifier: String?
        private let pendingLimit: Int?
        private let lock = NSLock()

        init(
            pending: [UNNotificationRequest] = [],
            delivered: Set<String> = [],
            settlementQueries: Int = 0,
            deliversNextAddedRequest: Bool = false,
            deliversAddedOnPendingQuery: Bool = false,
            deliversRemovedRequests: Bool = false,
            pendingLimit: Int? = nil
        ) {
            self.pending = Dictionary(
                pending.map { ($0.identifier, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            self.delivered = delivered
            self.settlementQueriesRemaining = settlementQueries
            self.deliversNextAddedRequest = deliversNextAddedRequest
            self.deliversAddedOnPendingQuery = deliversAddedOnPendingQuery
            self.deliversRemovedRequests = deliversRemovedRequests
            self.pendingLimit = pendingLimit
        }

        private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }

        func pendingRequests() async -> [UNNotificationRequest] {
            withLock {
                if deliversAddedOnPendingQuery, let lastAddedIdentifier {
                    pending.removeValue(forKey: lastAddedIdentifier)
                    delivered.insert(lastAddedIdentifier)
                    deliversAddedOnPendingQuery = false
                }
                if !removalTargets.isEmpty {
                    if settlementQueriesRemaining > 0 {
                        settlementQueriesRemaining -= 1
                    }
                    if settlementQueriesRemaining == 0 {
                        for id in removalTargets {
                            pending.removeValue(forKey: id)
                        }
                        removalTargets.removeAll()
                    }
                }
                return Array(pending.values)
            }
        }

        func deliveredIdentifiers() async -> [String] {
            withLock {
                if deliversNextAddedRequest, let lastAddedIdentifier {
                    pending.removeValue(forKey: lastAddedIdentifier)
                    delivered.insert(lastAddedIdentifier)
                    deliversNextAddedRequest = false
                }
                return Array(delivered)
            }
        }

        func add(_ request: UNNotificationRequest) async throws {
            try withLock {
                if addFailuresRemaining > 0 {
                    addFailuresRemaining -= 1
                    throw AddFailure.injected
                }
                pending[request.identifier] = request
                lastAddedIdentifier = request.identifier
                if let pendingLimit, pending.count > pendingLimit {
                    let retained = Array(pending.values).sorted {
                        (lhs: UNNotificationRequest, rhs: UNNotificationRequest) -> Bool in
                        let lhsDate = (lhs.trigger as? UNCalendarNotificationTrigger)?
                            .nextTriggerDate() ?? .distantFuture
                        let rhsDate = (rhs.trigger as? UNCalendarNotificationTrigger)?
                            .nextTriggerDate() ?? .distantFuture
                        if lhsDate != rhsDate { return lhsDate < rhsDate }
                        return lhs.identifier < rhs.identifier
                    }.prefix(pendingLimit)
                    pending = Dictionary(
                        retained.map { ($0.identifier, $0) },
                        uniquingKeysWith: { _, latest in latest }
                    )
                }
            }
        }

        func removePendingRequests(withIdentifiers identifiers: [String]) async {
            withLock {
                for id in identifiers {
                    removalCalls[id, default: 0] += 1
                }
                if deliversRemovedRequests {
                    for id in identifiers where pending.removeValue(forKey: id) != nil {
                        delivered.insert(id)
                    }
                    deliversRemovedRequests = false
                    return
                }
                removalTargets.formUnion(identifiers.filter { pending[$0] != nil })
                if settlementQueriesRemaining == 0 {
                    for id in removalTargets {
                        pending.removeValue(forKey: id)
                    }
                    removalTargets.removeAll()
                }
            }
        }

        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
            withLock { delivered.subtract(identifiers) }
        }

        func snapshot() async -> Snapshot {
            withLock {
                Snapshot(
                    pendingTitles: pending.mapValues(\.content.title),
                    pendingThreadIdentifiers: pending.mapValues(\.content.threadIdentifier),
                    deliveredIdentifiers: delivered,
                    removalCalls: removalCalls
                )
            }
        }

        func markDelivered(_ identifier: String) {
            _ = withLock { delivered.insert(identifier) }
        }

        func failNextAdds(_ count: Int) {
            withLock { addFailuresRemaining = count }
        }

        func settleRemovals() {
            withLock {
                for id in removalTargets {
                    pending.removeValue(forKey: id)
                }
                removalTargets.removeAll()
                settlementQueriesRemaining = 0
            }
        }
    }

    private let due = ISO8601.date(from: "2026-05-20T09:30:00.000Z")!  // a Wednesday

    private func habit(_ freq: HabitFrequency, enabled: Bool = true, hasDue: Bool = true) -> Item {
        var item = Item(type: .habit, title: "H", listId: "inbox", frequency: freq, goalPerCycle: 1)
        if hasDue { item.due = due }
        item.reminder = Reminder(enabled: enabled)
        return item
    }

    /// Hour/minute the scheduler should extract from `due`, in the same calendar
    /// it uses — so the assertion is timezone-independent.
    private var expectedTime: DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: due)
    }

    private func request(
        id: UUID = UUID(),
        title: String = "Existing",
        fireDate: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        return UNNotificationRequest(
            identifier: id.uuidString,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        )
    }

    @Test func dailyReminderRepeatsAtTheDueTime() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.daily))
        #expect(triggers.count == 1)
        let t = triggers[0].trigger
        #expect(t.repeats)
        #expect(t.dateComponents.hour == expectedTime.hour)
        #expect(t.dateComponents.minute == expectedTime.minute)
        #expect(t.dateComponents.weekday == nil, "a daily reminder is not pinned to a weekday")
    }

    @Test func weeklyReminderMatchesTheDueWeekday() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekly))
        #expect(triggers.count == 1)
        let t = triggers[0].trigger
        #expect(t.repeats)
        #expect(t.dateComponents.weekday == Calendar.current.component(.weekday, from: due))
        #expect(t.dateComponents.hour == expectedTime.hour)
    }

    @Test func monthlyReminderMatchesTheDueDayOfMonth() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.monthly))
        #expect(triggers.count == 1)
        let t = triggers[0].trigger
        #expect(t.repeats)
        #expect(t.dateComponents.day == Calendar.current.component(.day, from: due))
        #expect(t.dateComponents.weekday == nil)
    }

    @Test func reminderExtractsFloatingComponentsInThePersistedSourceZone() {
        var item = habit(.weekly)
        item.due = ISO8601.date(from: "2026-05-20T23:30:00.000Z")
        item.dueTimeZone = "Australia/Brisbane"
        let sourceCalendar = HabitReminderSchedule.calendar(
            timeZoneIdentifier: item.dueTimeZone
        )
        let due = item.due!

        let trigger = NotificationScheduler.habitTriggers(for: item)[0].trigger

        #expect(trigger.dateComponents.hour == sourceCalendar.component(.hour, from: due))
        #expect(trigger.dateComponents.minute == sourceCalendar.component(.minute, from: due))
        #expect(trigger.dateComponents.weekday == sourceCalendar.component(.weekday, from: due))
        #expect(trigger.dateComponents.timeZone == nil, "delivery must float in the current local zone")
    }

    @Test func monthlyReminderClampsUnsupportedMonthEndToARepeatableDay() {
        var item = habit(.monthly)
        item.due = ISO8601.date(from: "2026-01-31T09:30:00.000Z")
        item.dueTimeZone = "UTC"

        let trigger = NotificationScheduler.habitTriggers(for: item)[0].trigger

        #expect(trigger.dateComponents.day == 28)
        #expect(trigger.dateComponents.hour == 9)
        #expect(trigger.dateComponents.minute == 30)
    }

    // MARK: - Legacy raw frequencies normalize

    @Test func hourlyNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.hourly))
        #expect(triggers.count == 1)
        let t = triggers[0].trigger
        #expect(t.dateComponents.hour == expectedTime.hour, "a legacy hourly habit must NOT ping every hour — it reads as daily")
        #expect(t.dateComponents.minute == expectedTime.minute)
        #expect(t.dateComponents.weekday == nil)
    }

    @Test func weekdaysNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekdays))
        #expect(triggers.count == 1, "no per-weekday fan-out — one trigger per habit")
        #expect(triggers[0].trigger.dateComponents.weekday == nil)
        #expect(triggers[0].suffix == "", "no wd.<n> suffixes once normalized")
    }

    @Test func weekendsNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekends))
        #expect(triggers.count == 1)
        #expect(triggers[0].trigger.dateComponents.weekday == nil)
    }

    @Test func customNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.custom))
        #expect(triggers.count == 1)
        #expect(triggers[0].trigger.dateComponents.weekday == nil)
        #expect(triggers[0].trigger.dateComponents.hour == expectedTime.hour)
    }

    @Test func fortnightlyNormalizesToWeekly() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.fortnightly))
        #expect(triggers.count == 1)
        #expect(triggers[0].trigger.dateComponents.weekday == Calendar.current.component(.weekday, from: due))
    }

    @Test func quarterlyNormalizesToMonthly() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.everyThreeMonths))
        #expect(triggers.count == 1)
        #expect(triggers[0].trigger.dateComponents.day == Calendar.current.component(.day, from: due))
        #expect(triggers[0].trigger.dateComponents.month == nil, "monthly cadence — not pinned to one month of the year")
    }

    // MARK: - Guards

    @Test func noDueDateYieldsNoTriggers() {
        #expect(NotificationScheduler.habitTriggers(for: habit(.daily, hasDue: false)).isEmpty)
    }

    @Test func nonHabitYieldsNoTriggers() {
        var task = Item(type: .task, title: "T", listId: "inbox")
        task.due = due
        task.reminder = Reminder(enabled: true)
        #expect(NotificationScheduler.habitTriggers(for: task).isEmpty)
    }

    // MARK: - Single reminders

    @Test func singleReminderUsesCompletionSemanticsForNotes() {
        var note = Item(type: .note, title: "N", listId: "inbox", done: true)
        note.due = due
        note.reminder = Reminder(enabled: true)

        #expect(NotificationScheduler.singleReminderFireDate(for: note, now: due.addingTimeInterval(-60)) == due)
    }

    @Test func singleReminderSkipsCompletedTask() {
        var task = Item(type: .task, title: "T", listId: "inbox", done: true)
        task.due = due
        task.reminder = Reminder(enabled: true)

        #expect(NotificationScheduler.singleReminderFireDate(for: task, now: due.addingTimeInterval(-60)) == nil)
    }

    @Test func singleReminderSkipsCompletedCompletableEvent() {
        var event = Item(type: .event, title: "E", listId: "inbox", done: true, completable: true)
        event.due = due
        event.end = due.addingTimeInterval(3_600)
        event.reminder = Reminder(enabled: true)

        #expect(NotificationScheduler.singleReminderFireDate(for: event, now: due.addingTimeInterval(-60)) == nil)
    }

    @Test func singleReminderUsesEventCompletionSemantics() {
        var event = Item(type: .event, title: "E", listId: "inbox", done: true)
        event.due = due
        event.end = due.addingTimeInterval(3_600)
        event.reminder = Reminder(enabled: true)

        #expect(NotificationScheduler.singleReminderFireDate(for: event, now: due.addingTimeInterval(-60)) == due)
    }

    @Test func singleReminderIgnoresHabitsBecauseTheyUseRepeatingTriggers() {
        let item = habit(.daily)

        #expect(NotificationScheduler.singleReminderFireDate(for: item, now: due.addingTimeInterval(-60)) == nil)
    }

    @Test func deliveryStatusDistinguishesPermissionFromAlertPresentation() {
        #expect(NotificationScheduler.deliveryStatus(
            authorizationStatus: .notDetermined,
            notificationCenterSetting: .disabled,
            alertSetting: .disabled,
            scheduledDeliverySetting: .disabled
        ) == .notDetermined)
        #expect(NotificationScheduler.deliveryStatus(
            authorizationStatus: .denied,
            notificationCenterSetting: .enabled,
            alertSetting: .enabled,
            scheduledDeliverySetting: .disabled
        ) == .denied)
        #expect(NotificationScheduler.deliveryStatus(
            authorizationStatus: .provisional,
            notificationCenterSetting: .enabled,
            alertSetting: .enabled,
            scheduledDeliverySetting: .disabled
        ) == .quiet)
        #expect(NotificationScheduler.deliveryStatus(
            authorizationStatus: .authorized,
            notificationCenterSetting: .enabled,
            alertSetting: .disabled,
            scheduledDeliverySetting: .disabled
        ) == .quiet)
        #expect(NotificationScheduler.deliveryStatus(
            authorizationStatus: .authorized,
            notificationCenterSetting: .disabled,
            alertSetting: .enabled,
            scheduledDeliverySetting: .disabled
        ) == .quiet)
        #expect(NotificationScheduler.deliveryStatus(
            authorizationStatus: .authorized,
            notificationCenterSetting: .enabled,
            alertSetting: .enabled,
            scheduledDeliverySetting: .enabled
        ) == .summarized)
        #expect(NotificationScheduler.deliveryStatus(
            authorizationStatus: .authorized,
            notificationCenterSetting: .enabled,
            alertSetting: .enabled,
            scheduledDeliverySetting: .disabled
        ) == .enabled)
    }

    // MARK: - Queue ordering and reconciliation

    @Test(.timeLimit(.minutes(1)))
    func delayedRemovalReplaysOnlyTheLatestScheduleIntent() async throws {
        let id = UUID()
        let base = id.uuidString
        let oldRequest = UNNotificationRequest(
            identifier: base,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let center = FakeNotificationCenter(
            pending: [oldRequest],
            settlementQueries: 100
        )
        let scheduler = NotificationScheduler(center: center)

        await scheduler.cancel(id)
        var first = Item(
            id: id,
            type: .task,
            title: "First replacement",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )
        await scheduler.schedule(first)
        first.title = "Latest replacement"
        await scheduler.schedule(first)

        center.settleRemovals()
        try await Task.sleep(for: .milliseconds(50))
        let snapshot = await center.snapshot()
        let itemTitles = snapshot.pendingTitles.filter { $0.key.hasPrefix(base) }
        #expect(itemTitles.count == 1)
        #expect(itemTitles.values.first == "Latest replacement")
        #expect(snapshot.removalCalls[base] == 1,
                "one cancellation generation must issue exactly one base removal")
    }

    @Test(.timeLimit(.minutes(1)))
    func failedReplacementKeepsTheOldRequestUntilRetrySucceeds() async throws {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        var item = Item(
            type: .task,
            title: "Known-good reminder",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )
        await scheduler.schedule(item)
        let first = await center.snapshot()
        let firstIdentifier = try #require(
            first.pendingTitles.first { $0.key.hasPrefix(item.id.uuidString) }?.key
        )

        center.failNextAdds(1)
        item.title = "Latest durable reminder"
        item.modifiedAt = .now.addingTimeInterval(1)
        await scheduler.schedule(item)

        let failed = await center.snapshot()
        #expect(failed.pendingTitles[firstIdentifier] == "Known-good reminder")

        try await Task.sleep(for: .milliseconds(700))
        let retried = await center.snapshot()
        let itemTitles = retried.pendingTitles.filter {
            $0.key.hasPrefix(item.id.uuidString)
        }
        #expect(itemTitles.count == 1)
        #expect(itemTitles.values.first == item.title)
    }

    @Test func fullQueueAtomicallyMigratesTheItemsExistingSlot() async {
        let item = Item(
            type: .task,
            title: "Updated at capacity",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )
        let oldContent = UNMutableNotificationContent()
        oldContent.title = "Stale at capacity"
        let old = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: oldContent,
            trigger: nil
        )
        let unrelated = (0..<(NotificationScheduler.pendingLimit - 1)).map { _ in
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: UNMutableNotificationContent(),
                trigger: nil
            )
        }
        let center = FakeNotificationCenter(pending: [old] + unrelated)
        let scheduler = NotificationScheduler(center: center)

        await scheduler.schedule(item)

        let snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.count == NotificationScheduler.pendingLimit)
        #expect(snapshot.pendingTitles[item.id.uuidString] == item.title)
    }

    @Test func fullQueueLetsANearerNewReminderCompeteByFireDate() async {
        let existing = (0..<NotificationScheduler.pendingLimit).map { offset in
            request(
                fireDate: .now.addingTimeInterval(
                    (48 * 3_600) + TimeInterval(offset * 60)
                )
            )
        }
        let center = FakeNotificationCenter(
            pending: existing,
            pendingLimit: NotificationScheduler.pendingLimit
        )
        let scheduler = NotificationScheduler(center: center)
        let urgent = Item(
            type: .task,
            title: "Sooner than the full queue",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )

        await scheduler.schedule(urgent)

        let snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.count == NotificationScheduler.pendingLimit)
        #expect(snapshot.pendingTitles.contains { identifier, title in
            identifier.hasPrefix(urgent.id.uuidString) && title == urgent.title
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func nearerReminderRetainsTheDisplacedItemUntilCapacityReturns() async throws {
        let center = FakeNotificationCenter(
            pendingLimit: NotificationScheduler.pendingLimit
        )
        let scheduler = NotificationScheduler(center: center)
        let existingItems = (0..<NotificationScheduler.pendingLimit).map { offset in
            Item(
                type: .task,
                title: "Queued \(offset)",
                listId: ItemList.inboxId,
                due: .now.addingTimeInterval(
                    (48 * 3_600) + TimeInterval(offset * 60)
                ),
                reminder: Reminder(enabled: true)
            )
        }
        for item in existingItems {
            await scheduler.schedule(item)
        }
        let urgent = Item(
            type: .task,
            title: "Urgent",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )

        await scheduler.schedule(urgent)
        var snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.count == NotificationScheduler.pendingLimit)
        #expect(snapshot.pendingTitles.keys.contains {
            $0.hasPrefix(urgent.id.uuidString)
        })
        #expect(existingItems.contains { displaced in
            snapshot.pendingTitles.keys.contains {
                $0.hasPrefix(displaced.id.uuidString)
            } == false
        })

        await scheduler.cancel(urgent.id)
        try await Task.sleep(for: .milliseconds(700))

        snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.count == NotificationScheduler.pendingLimit)
        for item in existingItems {
            #expect(snapshot.pendingTitles.keys.contains {
                $0.hasPrefix(item.id.uuidString)
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func omittedLaterReminderRetriesAfterAnotherSlotIsFreed() async throws {
        let existing = (0..<NotificationScheduler.pendingLimit).map { offset in
            request(
                fireDate: .now.addingTimeInterval(
                    3_600 + TimeInterval(offset * 60)
                )
            )
        }
        let center = FakeNotificationCenter(
            pending: existing,
            pendingLimit: NotificationScheduler.pendingLimit
        )
        let scheduler = NotificationScheduler(center: center)
        let later = Item(
            type: .task,
            title: "Waiting for a slot",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(7 * 24 * 3_600),
            reminder: Reminder(enabled: true)
        )

        await scheduler.schedule(later)
        var snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.keys.contains {
            $0.hasPrefix(later.id.uuidString)
        } == false)

        await center.removePendingRequests(
            withIdentifiers: [try #require(existing.first?.identifier)]
        )
        try await Task.sleep(for: .milliseconds(700))

        snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.count == NotificationScheduler.pendingLimit)
        #expect(snapshot.pendingTitles.contains { identifier, title in
            identifier.hasPrefix(later.id.uuidString) && title == later.title
        })
    }

    @Test func newlyFiredReplacementIsNotClearedAsStaleHistory() async {
        let center = FakeNotificationCenter(deliversNextAddedRequest: true)
        let scheduler = NotificationScheduler(center: center)
        let item = Item(
            type: .task,
            title: "Boundary fire",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )

        await scheduler.schedule(item)

        let snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.keys.contains {
            $0.hasPrefix(item.id.uuidString)
        } == false)
        #expect(snapshot.deliveredIdentifiers.contains {
            $0.hasPrefix(item.id.uuidString)
        })
    }

    @Test func predecessorFiringWhileItsReplacementSettlesRemainsDelivered() async {
        let id = UUID()
        let oldIdentifier = id.uuidString
        let old = UNNotificationRequest(
            identifier: oldIdentifier,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let center = FakeNotificationCenter(
            pending: [old],
            deliversRemovedRequests: true
        )
        let scheduler = NotificationScheduler(center: center)
        var replacement = Item(
            id: id,
            type: .task,
            title: "Future replacement",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )
        replacement.modifiedAt = .now.addingTimeInterval(1)

        await scheduler.schedule(replacement)
        try? await Task.sleep(for: .milliseconds(50))

        let snapshot = await center.snapshot()
        #expect(snapshot.deliveredIdentifiers.contains(oldIdentifier))
        #expect(snapshot.pendingTitles.contains { identifier, title in
            identifier.hasPrefix(id.uuidString)
                && identifier != oldIdentifier
                && title == replacement.title
        })
    }

    @Test func replacementFiringBeforePendingVerificationIsNotRetried() async {
        let center = FakeNotificationCenter(deliversAddedOnPendingQuery: true)
        let scheduler = NotificationScheduler(center: center)
        let item = Item(
            type: .task,
            title: "Immediate boundary fire",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )

        await scheduler.schedule(item)
        try? await Task.sleep(for: .milliseconds(600))

        let snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.keys.contains {
            $0.hasPrefix(item.id.uuidString)
        } == false)
        #expect(snapshot.deliveredIdentifiers.filter {
            $0.hasPrefix(item.id.uuidString)
        }.count == 1)
    }

    @Test func schedulingHabitPreservesDeliveredHistoryAndKeepsItsRepeat() async {
        var item = habit(.daily)
        item.id = UUID()
        item.due = .now.addingTimeInterval(-3_600)
        let center = FakeNotificationCenter(
            delivered: [item.id.uuidString]
        )
        let scheduler = NotificationScheduler(center: center)

        await scheduler.schedule(item)

        let snapshot = await center.snapshot()
        #expect(snapshot.deliveredIdentifiers.contains(item.id.uuidString))
        #expect(snapshot.pendingTitles.keys.contains {
            $0.hasPrefix(item.id.uuidString)
        })
    }

    @Test func coldLaunchReconciliationPreservesDeliveredHabitAndReusesItsRepeat() async throws {
        var item = habit(.daily)
        item.id = UUID()
        let center = FakeNotificationCenter()

        await NotificationScheduler(center: center).schedule(item)
        let initiallyScheduled = await center.snapshot()
        let requestIdentifier = try #require(
            initiallyScheduled.pendingTitles.keys.first {
                $0.hasPrefix(item.id.uuidString)
            }
        )
        center.markDelivered(requestIdentifier)

        // A new actor models the next process launch: no in-memory reuse hints
        // survive, so the durable request metadata must still keep one repeat.
        await NotificationScheduler(center: center).reconcile([item])

        let reconciled = await center.snapshot()
        let habitPending = reconciled.pendingTitles.keys.filter {
            $0.hasPrefix(item.id.uuidString)
        }
        #expect(habitPending == [requestIdentifier])
        #expect(reconciled.deliveredIdentifiers.contains(requestIdentifier))
    }

    @Test(arguments: [false, true])
    func disablingOrDeletingHabitClearsPendingAndDeliveredReminder(deleted: Bool) async throws {
        var item = habit(.daily)
        item.id = UUID()
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center)

        await scheduler.schedule(item)
        let scheduled = await center.snapshot()
        let requestIdentifier = try #require(scheduled.pendingTitles.keys.first {
            $0.hasPrefix(item.id.uuidString)
        })
        center.markDelivered(requestIdentifier)
        if deleted {
            item.deletedAt = .now
        } else {
            item.reminder = Reminder(enabled: false)
        }

        await scheduler.schedule(item)

        let cleared = await center.snapshot()
        #expect(!cleared.pendingTitles.keys.contains(requestIdentifier))
        #expect(!cleared.deliveredIdentifiers.contains(requestIdentifier))
    }

    @Test func acknowledgingHabitClearsOnlyDeliveredHistoryAndKeepsItsRepeat() async throws {
        var item = habit(.daily)
        item.id = UUID()
        let unrelatedIdentifier = UUID().uuidString
        let center = FakeNotificationCenter(delivered: [unrelatedIdentifier])
        let scheduler = NotificationScheduler(center: center)

        await scheduler.schedule(item)
        let scheduled = await center.snapshot()
        let pendingIdentifier = try #require(scheduled.pendingTitles.keys.first {
            $0.hasPrefix(item.id.uuidString)
        })
        center.markDelivered(pendingIdentifier)

        await scheduler.acknowledgeDelivered(item.id)

        let acknowledged = await center.snapshot()
        #expect(acknowledged.pendingTitles[pendingIdentifier] == item.title)
        #expect(!acknowledged.deliveredIdentifiers.contains(pendingIdentifier))
        #expect(acknowledged.deliveredIdentifiers.contains(unrelatedIdentifier))
        #expect(
            acknowledged.pendingThreadIdentifiers[pendingIdentifier]
                == "habit.\(item.id.uuidString)"
        )
    }

    @Test func reconciliationPreservesRelevantDeliveredNotifications() async {
        let overdueId = UUID()
        var overdue = Item(
            id: overdueId,
            type: .task,
            title: "Already delivered",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(-3_600),
            reminder: Reminder(enabled: true)
        )
        overdue.done = false
        var repeatingHabit = habit(.daily)
        repeatingHabit.id = UUID()
        repeatingHabit.due = .now.addingTimeInterval(-3_600)
        let future = Item(
            type: .task,
            title: "Moved into the future",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )
        let staleId = UUID()
        let overduePending = UNNotificationRequest(
            identifier: overdueId.uuidString,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let center = FakeNotificationCenter(
            pending: [overduePending],
            delivered: [
                overdueId.uuidString,
                repeatingHabit.id.uuidString,
                future.id.uuidString,
                staleId.uuidString,
                "\(staleId.uuidString).wd.3"
            ]
        )
        let scheduler = NotificationScheduler(center: center)

        await scheduler.reconcile([overdue, repeatingHabit, future])

        let snapshot = await center.snapshot()
        #expect(snapshot.deliveredIdentifiers.contains(overdueId.uuidString))
        #expect(snapshot.deliveredIdentifiers.contains(repeatingHabit.id.uuidString))
        #expect(!snapshot.deliveredIdentifiers.contains(future.id.uuidString))
        #expect(!snapshot.deliveredIdentifiers.contains(staleId.uuidString))
        #expect(!snapshot.deliveredIdentifiers.contains("\(staleId.uuidString).wd.3"))
        #expect(snapshot.pendingTitles[overdueId.uuidString] == nil,
                "overdue delivered history must not preserve a stale pending request")
        #expect(snapshot.pendingTitles.first {
            $0.key.hasPrefix(future.id.uuidString)
        }?.value == future.title)
    }

    @Test func reconciliationReplacesPendingStateAndRemovesStaleRequests() async {
        let staleId = UUID()
        let staleRequest = UNNotificationRequest(
            identifier: staleId.uuidString,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let center = FakeNotificationCenter(pending: [staleRequest])
        let scheduler = NotificationScheduler(center: center)
        let upcoming = Item(
            type: .task,
            title: "Durable upcoming reminder",
            listId: ItemList.inboxId,
            due: .now.addingTimeInterval(3_600),
            reminder: Reminder(enabled: true)
        )

        await scheduler.reconcile([upcoming])

        let snapshot = await center.snapshot()
        #expect(snapshot.pendingTitles.first {
            $0.key.hasPrefix(upcoming.id.uuidString)
        }?.value == upcoming.title)
        #expect(snapshot.pendingTitles[staleId.uuidString] == nil)
    }
}
