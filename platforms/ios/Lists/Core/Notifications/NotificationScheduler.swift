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

    /// Schedule a notification for the item. No-op if reminder is disabled,
    /// the item has no due date, or the item is in the past / done.
    public func schedule(_ item: Item) async {
        cancel(item.id)

        guard !item.done,
              item.deletedAt == nil,
              let reminder = item.reminder, reminder.enabled,
              let fireDate = effectiveFireDate(for: item),
              fireDate > .now
        else { return }

        let content = UNMutableNotificationContent()
        content.title = item.title
        if !item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content.body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        content.sound = .default
        content.threadIdentifier = item.listId

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    public func cancel(_ id: UUID) {
        let key = id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [key])
        center.removeDeliveredNotifications(withIdentifiers: [key])
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
