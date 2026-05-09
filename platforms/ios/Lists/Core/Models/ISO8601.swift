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

    /// Used for date-only fields in habit completion logs and `due_all_day`
    /// items (e.g. `2026-05-09`).
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? dayFormatter.date(from: string)
    }

    static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
