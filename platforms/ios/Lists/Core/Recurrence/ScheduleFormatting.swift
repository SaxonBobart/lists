import Foundation

enum ScheduleFormatting {
    static func relativeDateSubtitle(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return longDate(date)
    }

    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter.string(from: date)
    }

    static func timeSubtitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func defaultEndRepeat(now: Date = .now, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .month, value: 6, to: startOfToday) ?? now
    }

    static func formatUntil(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func parseUntil(_ string: String, calendar: Calendar = .current) -> Date? {
        func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }

        if string.hasSuffix("Z") {
            let utc = TimeZone(identifier: "UTC")!
            return formatter("yyyyMMdd'T'HHmmss'Z'", timeZone: utc).date(from: string)
        }

        if string.contains("T") {
            return formatter("yyyyMMdd'T'HHmmss", timeZone: calendar.timeZone).date(from: string)
        }

        return formatter("yyyyMMdd", timeZone: calendar.timeZone).date(from: string)
    }
}
