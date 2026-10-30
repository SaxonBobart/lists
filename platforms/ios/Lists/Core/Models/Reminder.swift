import Foundation

/// The reminder block. Shared by dated documents. See PRODUCT-SPEC.md §4.1.
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
    /// Explicitly removed occurrences; ISO dates keep Markdown exports readable.
    public var excludedDates: [String]

    public init(rrule: String, excludedDates: [String] = []) {
        self.rrule = rrule
        self.excludedDates = excludedDates
    }
    public func excludes(_ date: Date) -> Bool {
        excludedDates.contains { ISO8601.date(from: $0).map { abs($0.timeIntervalSince(date)) < 1 } ?? false }
    }
    private enum CodingKeys: String, CodingKey { case rrule; case excludedDates = "excluded_dates" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rrule = try c.decode(String.self, forKey: .rrule)
        excludedDates = try c.decodeIfPresent([String].self, forKey: .excludedDates) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rrule, forKey: .rrule)
        if !excludedDates.isEmpty { try c.encode(excludedDates, forKey: .excludedDates) }
    }
}
