import Foundation

/// Pure recurrence expansion. Given a fired `due` date and the RRULE string the
/// app stores in `Recurrence.rrule`, computes the next occurrence — or `nil`
/// when the rule is unparseable or the series has ended.
///
/// Parses only the fields the compose UI actually emits today
/// (`FREQ`, `INTERVAL`, `BYDAY`, `UNTIL`); unknown fields are ignored. Total and
/// dependency-free: never throws, and an unparseable rule ends the series safely.
enum RecurrenceEngine {

    /// Next occurrence strictly after `from`, advancing by the rule. Returns nil
    /// when the rule can't be parsed or the next date would be past `UNTIL`.
    /// `from` is treated as the anchor occurrence, so INTERVAL counts from it.
    ///
    /// Handles `FREQ`, `INTERVAL`, `UNTIL`, weekly/monthly/yearly `BYDAY` (incl.
    /// ordinal prefixes like `2SU`/`-1FR`), `BYMONTHDAY`, and `BYMONTH`.
    static func nextOccurrence(after from: Date, rrule: String,
                               calendar: Calendar = .current) -> Date? {
        let parts = RRuleParts.parse(rrule)

        guard let freq = parts["FREQ"] else { return nil }
        let interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)
        let until = parts["UNTIL"].flatMap { ScheduleFormatting.parseUntil($0, calendar: calendar) }

        let next: Date?
        switch freq {
        case "HOURLY":
            next = calendar.date(byAdding: .hour, value: interval, to: from)
        case "DAILY":
            next = calendar.date(byAdding: .day, value: interval, to: from)
        case "WEEKLY":
            if let byday = parts["BYDAY"] {
                next = nextWeekly(after: from, byday: byday, interval: interval, calendar: calendar)
            } else {
                next = calendar.date(byAdding: .weekOfYear, value: interval, to: from)
            }
        case "MONTHLY":
            if let bymd = parts["BYMONTHDAY"] {
                next = nextMonthlyByDay(after: from, days: parseInts(bymd), interval: interval, calendar: calendar)
            } else if let ord = parts["BYDAY"].flatMap(parseOrdinalDay) {
                next = nextMonthlyOrdinal(after: from, ordinal: ord.ordinal, weekday: ord.weekday,
                                          interval: interval, calendar: calendar)
            } else {
                next = calendar.date(byAdding: .month, value: interval, to: from)
            }
        case "YEARLY":
            let months = (parts["BYMONTH"].map(parseInts) ?? []).sorted()
            if months.isEmpty {
                next = calendar.date(byAdding: .year, value: interval, to: from)
            } else {
                next = nextYearly(after: from, months: months,
                                  ordinalDay: parts["BYDAY"].flatMap(parseOrdinalDay),
                                  interval: interval, calendar: calendar)
            }
        default:
            next = nil
        }

        guard let n = next else { return nil }
        // UNTIL is authored as a day (the end-repeat picker yields a date), so
        // compare day-granular in the series' calendar. "End Dec 31" must
        // include Dec 31's occurrence in every timezone, not drop it or allow
        // an extra one by up to the UTC offset.
        if let until, calendar.startOfDay(for: n) > calendar.startOfDay(for: until) { return nil }
        return n
    }

    /// A calendar pinned to a stored `dueTimeZone` identifier so a repeating
    /// task advances in the zone it was authored in, not wherever the device
    /// happens to be now. Otherwise "every weekday 9am" set in New York
    /// re-anchors to a different wall-clock hour or day after travel/DST.
    /// Falls back to `.current` when the identifier is nil or unrecognised.
    static func calendar(forTimeZone identifier: String?) -> Calendar {
        var calendar = Calendar.current
        if let identifier, let timeZone = TimeZone(identifier: identifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    // MARK: Parsing helpers

    private static let weekdayMap: [String: Int] =
        ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    private static func parseInts(_ s: String) -> [Int] {
        s.split(separator: ",").compactMap { Int($0) }
    }

    /// Parse an ordinal BYDAY token ("2SU", "-1FR") → (ordinal, calendar weekday).
    /// Returns nil for plain weekday codes (those are handled by `nextWeekly`).
    private static func parseOrdinalDay(_ byday: String) -> (ordinal: Int, weekday: Int)? {
        let token = byday.split(separator: ",").first.map(String.init) ?? byday
        let code = String(token.suffix(2)).uppercased()
        let prefix = String(token.dropLast(2))
        guard !prefix.isEmpty, let n = Int(prefix), let wd = weekdayMap[code] else { return nil }
        return (n, wd)
    }

    // MARK: Frequency expanders

    /// WEEKLY + BYDAY: next selected weekday, honouring INTERVAL weeks measured
    /// from `from`'s week. Steps day-by-day, so the wall-clock time is preserved.
    private static func nextWeekly(after from: Date, byday: String,
                                   interval: Int, calendar: Calendar) -> Date? {
        let wanted = Set(byday.split(separator: ",").compactMap { weekdayMap[$0.uppercased()] })
        guard !wanted.isEmpty, let fromWeek = calendar.dateInterval(of: .weekOfYear, for: from)?.start else { return nil }
        for offset in 1...(7 * interval + 7) {
            guard let cand = calendar.date(byAdding: .day, value: offset, to: from),
                  wanted.contains(calendar.component(.weekday, from: cand)),
                  let candWeek = calendar.dateInterval(of: .weekOfYear, for: cand)?.start else { continue }
            let weeks = (calendar.dateComponents([.day], from: fromWeek, to: candWeek).day ?? 0) / 7
            if weeks % interval == 0 { return cand }
        }
        return nil
    }

    /// MONTHLY + BYMONTHDAY: next listed day-of-month, honouring INTERVAL months.
    private static func nextMonthlyByDay(after from: Date, days: [Int],
                                         interval: Int, calendar: Calendar) -> Date? {
        let sortedDays = days.filter { (1...31).contains($0) }.sorted()
        guard !sortedDays.isEmpty else { return nil }
        for k in 0...24 {
            guard let (y, m) = monthYear(from: from, addingMonths: k * interval, calendar: calendar) else { continue }
            let dim = daysInMonth(year: y, month: m, calendar: calendar)
            for d in sortedDays where d <= dim {
                if let cand = date(year: y, month: m, day: d, timeFrom: from, calendar: calendar), cand > from {
                    return cand
                }
            }
        }
        return nil
    }

    /// MONTHLY + ordinal BYDAY (e.g. "2SU"): the Nth weekday of each active month.
    private static func nextMonthlyOrdinal(after from: Date, ordinal: Int, weekday: Int,
                                           interval: Int, calendar: Calendar) -> Date? {
        for k in 0...24 {
            guard let (y, m) = monthYear(from: from, addingMonths: k * interval, calendar: calendar) else { continue }
            if let cand = nthWeekday(ordinal: ordinal, weekday: weekday, year: y, month: m,
                                     timeFrom: from, calendar: calendar), cand > from {
                return cand
            }
        }
        return nil
    }

    /// YEARLY + BYMONTH, optionally refined by an ordinal weekday. Without an
    /// ordinal, keeps `from`'s day-of-month (clamped to the month's length).
    private static func nextYearly(after from: Date, months: [Int],
                                   ordinalDay: (ordinal: Int, weekday: Int)?,
                                   interval: Int, calendar: Calendar) -> Date? {
        let fromYear = calendar.component(.year, from: from)
        let fromDay = calendar.component(.day, from: from)
        for k in 0...20 {
            let y = fromYear + k * interval
            for m in months {
                let cand: Date?
                if let ord = ordinalDay {
                    cand = nthWeekday(ordinal: ord.ordinal, weekday: ord.weekday, year: y, month: m,
                                      timeFrom: from, calendar: calendar)
                } else {
                    let d = min(fromDay, daysInMonth(year: y, month: m, calendar: calendar))
                    cand = date(year: y, month: m, day: d, timeFrom: from, calendar: calendar)
                }
                if let cand, cand > from { return cand }
            }
        }
        return nil
    }

    // MARK: Date math helpers

    /// Year/month obtained by shifting `from` by `n` whole months (day-agnostic).
    private static func monthYear(from: Date, addingMonths n: Int, calendar: Calendar) -> (year: Int, month: Int)? {
        let y = calendar.component(.year, from: from)
        let m = calendar.component(.month, from: from)
        guard let firstOfMonth = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
              let shifted = calendar.date(byAdding: .month, value: n, to: firstOfMonth) else { return nil }
        return (calendar.component(.year, from: shifted), calendar.component(.month, from: shifted))
    }

    private static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: d) else { return 31 }
        return range.count
    }

    /// A date at the given year/month/day with the time-of-day copied from
    /// `timeFrom`. DST-robust: the day is anchored at noon (an hour a
    /// spring-forward can never skip) and the time set via
    /// `date(bySettingHour:)`, whose next-time policy resolves a nonexistent
    /// wall-clock by rolling forward instead of silently dropping the month's
    /// occurrence the way a raw `date(from: components)` build can.
    private static func date(year: Int, month: Int, day: Int, timeFrom: Date, calendar: Calendar) -> Date? {
        guard let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        else { return nil }
        let t = calendar.dateComponents([.hour, .minute, .second], from: timeFrom)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0,
                             second: t.second ?? 0, of: noon)
    }

    /// Date of the Nth `weekday` in a month (ordinal 1…5, or negative for "last").
    private static func nthWeekday(ordinal: Int, weekday: Int, year: Int, month: Int,
                                   timeFrom: Date, calendar: Calendar) -> Date? {
        let dim = daysInMonth(year: year, month: month, calendar: calendar)
        if ordinal < 0 {
            for d in stride(from: dim, through: 1, by: -1) {
                if let cand = date(year: year, month: month, day: d, timeFrom: timeFrom, calendar: calendar),
                   calendar.component(.weekday, from: cand) == weekday { return cand }
            }
            return nil
        }
        var count = 0
        for d in 1...dim {
            guard let cand = date(year: year, month: month, day: d, timeFrom: timeFrom, calendar: calendar) else { continue }
            if calendar.component(.weekday, from: cand) == weekday {
                count += 1
                if count == ordinal { return cand }
            }
        }
        return nil
    }
}
