import Foundation

/// Single source of truth for date <-> string conversion at the file-format
/// boundary. The on-disk format is ISO 8601 with internet date-time + fractional
/// seconds (e.g. `2026-05-09T15:30:00.000Z`), per `shared/format/`.
enum ISO8601 {
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// UTC day formatter — habit cycle keys and the heatmap's day grouping
    /// bucket in UTC by convention.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Local-calendar day formatter. An all-day date is a calendar DAY, not
    /// an instant: "June 12" must stay June 12 wherever the device travels.
    /// So all-day fields encode as the local day and a date-only string
    /// decodes at local start-of-day — which also keeps `SmartList`'s
    /// local-calendar Today/Scheduled bucketing on the right day. Computed, not
    /// cached: the device timezone can change mid-run.
    private static var localDayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? localDayFormatter.date(from: string)
    }

    static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Day string for all-day fields, derived in the device's local calendar
    /// (the day the user actually picked).
    static func localDayString(from date: Date) -> String {
        localDayFormatter.string(from: date)
    }
}
