import Foundation

enum ReminderPreferences {
    private static let defaultTimeMinutesKey = "lists.reminders.defaultTimeMinutes.v1"
    private static let fallbackMinutes = 9 * 60

    static func defaultTime(
        on date: Date = .now,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> Date {
        let minutes = defaultTimeMinutes(defaults: defaults)
        let hour = minutes / 60
        let minute = minutes % 60
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        ) ?? date
    }

    static func setDefaultTime(
        _ date: Date,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = min(max(components.hour ?? 9, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        defaults.set(hour * 60 + minute, forKey: defaultTimeMinutesKey)
    }

    private static func defaultTimeMinutes(defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: defaultTimeMinutesKey) != nil else {
            return fallbackMinutes
        }
        return min(max(defaults.integer(forKey: defaultTimeMinutesKey), 0), 23 * 60 + 59)
    }
}
