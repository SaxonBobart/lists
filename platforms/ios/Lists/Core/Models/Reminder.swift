import Foundation

/// The reminder block. Shared by tasks and habits. See PRODUCT-SPEC.md §4.1.
public struct Reminder: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var early: EarlyReminder?

    public init(enabled: Bool, early: EarlyReminder? = nil) {
        self.enabled = enabled
        self.early = early
    }
}

/// Optional "remind me X before due" offset. See PRODUCT-SPEC.md §4.1.1.
public struct EarlyReminder: Codable, Equatable, Sendable {
    public var value: Int
    public var unit: Unit

    public enum Unit: String, Codable, Sendable, CaseIterable {
        case minute, hour, day, week, month
    }

    public init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }
}

/// Triggers — universal data, device-restricted firing. See PRODUCT-SPEC.md §4.2.
public struct Triggers: Codable, Equatable, Sendable {
    public var alarm: TriggerToggle?
    public var location: LocationTrigger?

    public init(alarm: TriggerToggle? = nil, location: LocationTrigger? = nil) {
        self.alarm = alarm
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case alarm
        case location
        case legacyUrgent = "urgent"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alarm = try container.decodeIfPresent(TriggerToggle.self, forKey: .alarm)
            ?? container.decodeIfPresent(TriggerToggle.self, forKey: .legacyUrgent)
        location = try container.decodeIfPresent(LocationTrigger.self, forKey: .location)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(alarm, forKey: .alarm)
        try container.encodeIfPresent(location, forKey: .location)
    }
}

public struct TriggerToggle: Codable, Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}

public struct LocationTrigger: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var latitude: Double?
    public var longitude: Double?
    public var radius: Double?
    public var fire: Direction?

    public enum Direction: String, Codable, Sendable, CaseIterable {
        case arrive, leave
    }

    public init(
        enabled: Bool,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radius: Double? = nil,
        fire: Direction? = nil
    ) {
        self.enabled = enabled
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.fire = fire
    }
}

/// RFC 5545 RRULE wrapper. The string is opaque at this layer; recurrence
/// parsing, formatting, and expansion live in `Core/Recurrence`.
public struct Recurrence: Codable, Equatable, Sendable {
    public var rrule: String

    public init(rrule: String) {
        self.rrule = rrule
    }
}

/// Habit cadence. See PRODUCT-SPEC.md §3.2.
///
/// The full set still exists because old data and task-shaped code may reference
/// it, but a *habit* is locked to `habitCadences` (daily / weekly / monthly) so
/// its streak always reads as a day-, week-, or month-streak. Any other value a
/// stored habit carries is folded onto one of the three via `normalizedForHabit`.
public enum HabitFrequency: String, Codable, Sendable, CaseIterable {
    case hourly
    case daily
    case weekdays
    case weekends
    case weekly
    case fortnightly
    case monthly
    case everyThreeMonths = "every_three_months"
    case everySixMonths = "every_six_months"
    case yearly
    case custom

    /// The only cadences a habit may be set to.
    public static let habitCadences: [HabitFrequency] = [.daily, .weekly, .monthly]

    /// Collapse any legacy frequency onto daily / weekly / monthly. Sub-daily and
    /// day-filtered cadences read as daily; fortnightly as weekly; multi-month and
    /// yearly as monthly.
    public var normalizedForHabit: HabitFrequency {
        switch self {
        case .daily, .hourly, .weekdays, .weekends, .custom:
            return .daily
        case .weekly, .fortnightly:
            return .weekly
        case .monthly, .everyThreeMonths, .everySixMonths, .yearly:
            return .monthly
        }
    }
}

/// Wall-clock conversion for a repeating habit reminder that is still stored
/// through an `Item`'s legacy absolute `due` value.
///
/// `Item.dueTimeZone` records the zone whose weekday, month day, and time
/// components the person chose. Notification triggers intentionally omit a
/// timezone so those stored components continue to fire at the same local time
/// after travel.
enum HabitReminderSchedule {
    static let supportedMonthlyDays = 1...28

    static func calendar(timeZoneIdentifier: String?) -> Calendar {
        var calendar = Calendar.autoupdatingCurrent
        if let timeZoneIdentifier,
           let sourceTimeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = sourceTimeZone
        } else {
            calendar.timeZone = .autoupdatingCurrent
        }
        return calendar
    }

    static func normalizedReminderTime(
        _ date: Date,
        frequency: HabitFrequency,
        timeZoneIdentifier: String?
    ) -> Date {
        guard frequency.normalizedForHabit == .monthly else { return date }

        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let currentDay = calendar.component(.day, from: date)
        guard !supportedMonthlyDays.contains(currentDay) else { return date }

        var components = calendar.dateComponents(
            [.era, .year, .month, .hour, .minute, .second, .nanosecond],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.day = supportedMonthlyDays.upperBound
        return calendar.date(from: components) ?? date
    }

    static func summary(
        frequency: HabitFrequency,
        reminderTime: Date,
        timeZoneIdentifier: String?
    ) -> String {
        let frequency = frequency.normalizedForHabit
        let date = normalizedReminderTime(
            reminderTime,
            frequency: frequency,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let time = timeFormatter(calendar: calendar).string(from: date)

        switch frequency {
        case .daily:
            return "Every day at \(time)"
        case .weekly:
            let weekday = calendar.component(.weekday, from: date)
            return "Every \(weekdayName(weekday, calendar: calendar)) at \(time)"
        case .monthly:
            let day = calendar.component(.day, from: date)
            return "Every month on the \(ordinal(day)) at \(time)"
        default:
            return "Every day at \(time)"
        }
    }

    static func weekdayValues(calendar: Calendar) -> [Int] {
        (0..<7).map { offset in
            ((calendar.firstWeekday - 1 + offset) % 7) + 1
        }
    }

    static func weekdayName(_ weekday: Int, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        let symbols = formatter.weekdaySymbols ?? []
        guard symbols.indices.contains(weekday - 1) else { return "Day \(weekday)" }
        return symbols[weekday - 1]
    }

    static func ordinal(_ day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }

    static func replacingWeekday(
        _ weekday: Int,
        in date: Date,
        timeZoneIdentifier: String?
    ) -> Date {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let currentWeekday = calendar.component(.weekday, from: date)
        return calendar.date(
            byAdding: .day,
            value: weekday - currentWeekday,
            to: date
        ) ?? date
    }

    static func replacingMonthDay(
        _ day: Int,
        in date: Date,
        timeZoneIdentifier: String?
    ) -> Date {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        var components = calendar.dateComponents(
            [.era, .year, .month, .hour, .minute, .second, .nanosecond],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.day = min(
            max(day, supportedMonthlyDays.lowerBound),
            supportedMonthlyDays.upperBound
        )
        return calendar.date(from: components) ?? date
    }

    private static func timeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}
