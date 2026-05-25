import Foundation

/// Pure recurrence expansion (TASK-1 / REM-1). Given a fired `due` date and the
/// RRULE string the app stores in `Recurrence.rrule`, computes the next
/// occurrence — or `nil` when the rule is unparseable or the series has ended.
///
/// Parses only the fields the compose UI actually emits today
/// (`FREQ`, `INTERVAL`, `BYDAY`, `UNTIL`); unknown fields are ignored. Total and
/// dependency-free: never throws, and an unparseable rule ends the series safely.
enum RecurrenceEngine {

    /// Next occurrence strictly after `from`, advancing by the rule. Returns nil
    /// when the rule can't be parsed or the next date would be past `UNTIL`.
    static func nextOccurrence(after from: Date, rrule: String,
                               calendar: Calendar = .current) -> Date? {
        let parts = Dictionary(
            rrule.split(separator: ";").compactMap { part -> (String, String)? in
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0].uppercased(), kv[1]) : nil
            },
            uniquingKeysWith: { _, new in new })

        guard let freq = parts["FREQ"] else { return nil }
        let interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)
        let until = parts["UNTIL"].flatMap(Self.parseUntil)

        let next: Date?
        switch freq {
        case "HOURLY":  next = calendar.date(byAdding: .hour, value: interval, to: from)
        case "DAILY":   next = calendar.date(byAdding: .day, value: interval, to: from)
        case "WEEKLY":
            if let byday = parts["BYDAY"] {
                next = nextWeekday(after: from, byday: byday, intervalWeeks: interval, calendar: calendar)
            } else {
                next = calendar.date(byAdding: .weekOfYear, value: interval, to: from)
            }
        case "MONTHLY": next = calendar.date(byAdding: .month, value: interval, to: from)
        case "YEARLY":  next = calendar.date(byAdding: .year, value: interval, to: from)
        default:        next = nil
        }

        guard let n = next else { return nil }
        if let until, n > until { return nil }
        return n
    }

    private static func parseUntil(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    /// Smallest date after `from` whose weekday is in `byday`, preserving the
    /// time-of-day of `from`. Steps day-by-day, so the wall-clock time is kept.
    private static func nextWeekday(after from: Date, byday: String,
                                    intervalWeeks: Int, calendar: Calendar) -> Date? {
        let map: [String: Int] = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let wanted = Set(byday.split(separator: ",").compactMap { map[$0.uppercased()] })
        guard !wanted.isEmpty else { return nil }
        for offset in 1...(7 * max(1, intervalWeeks) + 7) {
            guard let cand = calendar.date(byAdding: .day, value: offset, to: from) else { continue }
            if wanted.contains(calendar.component(.weekday, from: cand)) { return cand }
        }
        return nil
    }
}
