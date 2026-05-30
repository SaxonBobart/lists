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
    public var urgent: TriggerToggle?
    public var location: LocationTrigger?

    public init(urgent: TriggerToggle? = nil, location: LocationTrigger? = nil) {
        self.urgent = urgent
        self.location = location
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
/// expansion lives elsewhere (out of scope for M0).
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
