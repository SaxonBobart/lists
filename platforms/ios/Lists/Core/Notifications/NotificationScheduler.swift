import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter`. Schedules / cancels notifications keyed
/// by item id. Urgent triggers (AlarmKit) stay deferred per
/// `project_m6_deferred` memory until the paid Apple Developer Program is
/// available.
public actor NotificationScheduler {

    public static let shared = NotificationScheduler()

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
    /// *repeating* schedule keyed to their frequency (REM-1).
    public func schedule(_ item: Item) async {
        cancel(item.id)

        guard item.deletedAt == nil,
              let reminder = item.reminder, reminder.enabled
        else { return }

        if item.type == .habit {
            // Repeating, frequency-keyed reminders. No `fireDate > now` guard —
            // a repeating trigger has no single fire date and habits never set `done`.
            for (suffix, trigger) in Self.habitTriggers(for: item) {
                let identifier = suffix.isEmpty ? item.id.uuidString : "\(item.id.uuidString).\(suffix)"
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: makeContent(for: item),
                    trigger: trigger
                )
                try? await center.add(request)
            }
            return
        }

        // Task: a single reminder at the (early-adjusted) due date.
        guard !item.done,
              let fireDate = effectiveFireDate(for: item),
              fireDate > .now
        else { return }

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: makeContent(for: item),
            trigger: trigger
        )
        try? await center.add(request)
    }

    public func cancel(_ id: UUID) {
        // Habits fan out into per-weekday identifiers; clear the bare id and every
        // possible weekday suffix so no repeating request is left orphaned.
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

    /// Repeating calendar triggers for a habit, keyed to its frequency, using the
    /// time-of-day from `item.due`. Weekday cadences fan out into one request per
    /// scheduled weekday (suffix `wd.<n>`). Gentle by design — no urgency, no guilt.
    ///
    /// Limitations (documented, kept safe — never spammy): `fortnightly` is
    /// approximated as weekly, and `everyThreeMonths` / `everySixMonths` fire
    /// annually on the due month/day until a finer scheduler exists.
    nonisolated public static func habitTriggers(
        for item: Item
    ) -> [(suffix: String, trigger: UNCalendarNotificationTrigger)] {
        guard item.type == .habit, let frequency = item.frequency, let due = item.due else { return [] }
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
        case .daily, .custom:
            return [("", trigger { $0.hour = hour; $0.minute = minute })]
        case .hourly:
            return [("", trigger { $0.minute = minute })]
        case .weekdays:
            return (2...6).map { wd in
                ("wd.\(wd)", trigger { $0.weekday = wd; $0.hour = hour; $0.minute = minute })
            }
        case .weekends:
            return [1, 7].map { wd in
                ("wd.\(wd)", trigger { $0.weekday = wd; $0.hour = hour; $0.minute = minute })
            }
        case .weekly, .fortnightly:
            let weekday = cal.component(.weekday, from: due)
            return [("", trigger { $0.weekday = weekday; $0.hour = hour; $0.minute = minute })]
        case .monthly:
            let day = cal.component(.day, from: due)
            return [("", trigger { $0.day = day; $0.hour = hour; $0.minute = minute })]
        case .everyThreeMonths, .everySixMonths, .yearly:
            let month = cal.component(.month, from: due)
            let day = cal.component(.day, from: due)
            return [("", trigger { $0.month = month; $0.day = day; $0.hour = hour; $0.minute = minute })]
        }
    }

    public func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Helpers

    /// Computes the actual fire date taking `reminder.early` offset into
    /// account.
    private func effectiveFireDate(for item: Item) -> Date? {
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
