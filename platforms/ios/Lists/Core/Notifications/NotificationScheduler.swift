import Foundation
import UserNotifications
import os

/// Wraps `UNUserNotificationCenter`. Schedules / cancels standard local
/// notifications keyed by item id.
///
/// Timezone convention: reminder *triggers* fire at the user's local wall-clock
/// (`Calendar.current`) — a 9am reminder means 9am wherever you are.
/// Habit cycle *keys* are pinned to UTC (`HabitCycle.key`). The two only
/// diverge around timezone changes near a cycle boundary, and the trigger side
/// is deliberately local because that's what a reminder time means to a person.
public actor NotificationScheduler {

    public static let shared = NotificationScheduler()

    /// iOS keeps only the soonest ~64 pending notifications per app and
    /// silently discards the rest. The cap can't be raised; what we can do is
    /// keep our usage small (one trigger per habit, see `habitTriggers`) and
    /// log loudly when the queue reaches the limit so a reminder that will
    /// never fire is at least diagnosable.
    public static let pendingLimit = 64

    private static let log = Logger(
        subsystem: "io.github.saxonbobart.lists", category: "notifications")

    private let center = UNUserNotificationCenter.current()

    public init() {}

    // MARK: - Authorization

    /// Returns true if the user granted permission, false if denied/error.
    @discardableResult
    public func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Schedule / cancel

    /// Schedule notification(s) for the item. No-op if the reminder is disabled
    /// or the item is deleted. Tasks fire once at their due date; habits fire on a
    /// *repeating* schedule keyed to their frequency.
    public func schedule(_ item: Item) async {
        cancel(item.id)

        guard item.deletedAt == nil,
              let reminder = item.reminder, reminder.enabled
        else { return }

        if item.type == .habit {
            // Repeating, frequency-keyed reminders. No `fireDate > now` guard —
            // a repeating trigger has no single fire date, and a completed
            // current cycle should not cancel future habit reminders.
            for (suffix, trigger) in Self.habitTriggers(for: item) {
                let identifier = suffix.isEmpty ? item.id.uuidString : "\(item.id.uuidString).\(suffix)"
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: makeContent(for: item),
                    trigger: trigger
                )
                await add(request, for: item)
            }
            await warnIfOverBudget()
            return
        }

        // Dated non-habit items: a single reminder at the (early-adjusted) due
        // date. For an event, `due` is its start.
        guard let fireDate = Self.singleReminderFireDate(for: item) else { return }

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: makeContent(for: item),
            trigger: trigger
        )
        await add(request, for: item)
        await warnIfOverBudget()
    }

    /// A failed registration must be visible, not vanish. `center.add` failures
    /// are logged with the request + item id so silent reminder loss is
    /// diagnosable from the console.
    private func add(_ request: UNNotificationRequest, for item: Item) async {
        do {
            try await center.add(request)
        } catch {
            Self.log.error("""
                Failed to schedule reminder \(request.identifier, privacy: .public) \
                for item \(item.id.uuidString, privacy: .public): \
                \(String(describing: error), privacy: .private)
                """)
        }
    }

    /// Hitting the iOS pending-notification cap is silent by design (the system
    /// just keeps the 64 soonest). Make it observable.
    private func warnIfOverBudget() async {
        let pending = await center.pendingNotificationRequests().count
        if pending >= Self.pendingLimit {
            Self.log.warning("""
                \(pending) pending notifications — iOS keeps only the soonest \
                \(Self.pendingLimit); later reminders will be silently dropped
                """)
        }
    }

    public func cancel(_ id: UUID) {
        // Habits used to fan out into per-weekday identifiers (`.wd.<n>`)
        // before cadence normalization moved them to one trigger; keep clearing every
        // possible suffix so requests scheduled by older builds aren't orphaned.
        let base = id.uuidString
        let ids = [base] + (1...7).map { "\(base).wd.\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func makeContent(for item: Item) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { content.body = body }
        content.sound = .default
        content.threadIdentifier = item.listId
        return content
    }

    /// Repeating calendar triggers for a habit, using the time-of-day from
    /// `item.due`. Gentle by design — no urgency, no guilt.
    ///
    /// The schedule is built from the habit's *normalized* cadence (daily /
    /// weekly / monthly) — the only cadences the habit UI offers, and the same
    /// basis `HabitCycle`/`HabitStats` bucket on. A legacy raw value (`hourly`,
    /// `weekdays`, `custom`, …) must never drive a reminder cadence the user
    /// can no longer see or edit. One trigger per habit also keeps the app far
    /// away from the 64-notification cap.
    nonisolated public static func habitTriggers(
        for item: Item
    ) -> [(suffix: String, trigger: UNCalendarNotificationTrigger)] {
        guard item.type == .habit, let raw = item.frequency, let due = item.due else { return [] }
        let frequency = raw.normalizedForHabit
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute], from: due)
        let hour = time.hour ?? 9
        let minute = time.minute ?? 0

        func trigger(_ build: (inout DateComponents) -> Void) -> UNCalendarNotificationTrigger {
            var dc = DateComponents()
            build(&dc)
            return UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        }

        switch frequency {
        case .daily:
            return [("", trigger { $0.hour = hour; $0.minute = minute })]
        case .weekly:
            let weekday = cal.component(.weekday, from: due)
            return [("", trigger { $0.weekday = weekday; $0.hour = hour; $0.minute = minute })]
        case .monthly:
            let day = cal.component(.day, from: due)
            return [("", trigger { $0.day = day; $0.hour = hour; $0.minute = minute })]
        default:
            return []  // unreachable: normalizedForHabit only yields the three cadences
        }
    }

    public func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Helpers

    nonisolated static func singleReminderFireDate(for item: Item, now: Date = .now) -> Date? {
        guard item.type != .habit,
              item.deletedAt == nil,
              item.reminder?.enabled == true,
              !item.isComplete(at: now),
              let fireDate = effectiveFireDate(for: item),
              fireDate > now else {
            return nil
        }
        return fireDate
    }

    /// Computes the actual fire date taking `reminder.early` offset into
    /// account.
    private nonisolated static func effectiveFireDate(for item: Item) -> Date? {
        guard let due = item.due else { return nil }
        guard let early = item.reminder?.early else { return due }
        let cal = Calendar.current
        let component: Calendar.Component
        switch early.unit {
        case .minute: component = .minute
        case .hour:   component = .hour
        case .day:    component = .day
        case .week:   component = .weekOfYear
        case .month:  component = .month
        }
        return cal.date(byAdding: component, value: -early.value, to: due) ?? due
    }
}
