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
    /// `from` is treated as the anchor occurrence, so INTERVAL counts from it.
    ///
    /// Handles `FREQ`, `INTERVAL`, `UNTIL`, weekly/monthly/yearly `BYDAY` (incl.
    /// ordinal prefixes like `2SU`/`-1FR`), `BYMONTHDAY`, and `BYMONTH`.
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
        let until = parts["UNTIL"].flatMap { Self.parseUntil($0, calendar: calendar) }

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
        // REC-3: UNTIL is *authored* as a day (the end-repeat picker yields a
        // date), so compare day-granular in the series' calendar — "end Dec 31"
        // must include Dec 31's occurrence in every timezone, not drop it (or
        // allow an extra one) by up to the UTC offset.
        if let until, calendar.startOfDay(for: n) > calendar.startOfDay(for: until) { return nil }
        return n
    }

    /// A calendar pinned to a stored `dueTimeZone` identifier (REC-1) so a
    /// repeating task advances in the zone it was authored in, not wherever the
    /// device happens to be now — otherwise "every weekday 9am" set in New York
    /// re-anchors to a different wall-clock hour (or day) after travel/DST.
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

    /// REC-5: app-authored rules always carry the full-UTC form, but imported
    /// or hand-edited RRULEs may use a floating local datetime or a bare date.
    /// All three forms must end the series — a parse failure here would read
    /// as "no UNTIL" and the series would repeat forever.
    private static func parseUntil(_ s: String, calendar: Calendar) -> Date? {
        func formatter(_ format: String, _ tz: TimeZone) -> DateFormatter {
            let f = DateFormatter()
            f.dateFormat = format
            f.timeZone = tz
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
        let utc = TimeZone(identifier: "UTC")!
        return formatter("yyyyMMdd'T'HHmmss'Z'", utc).date(from: s)
            ?? formatter("yyyyMMdd'T'HHmmss", calendar.timeZone).date(from: s)
            ?? formatter("yyyyMMdd", calendar.timeZone).date(from: s)
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
    /// `timeFrom`. DST-robust (REC-4): the day is anchored at noon (an hour a
    /// spring-forward can never skip) and the time set via
    /// `date(bySettingHour:)`, whose next-time policy resolves a nonexistent
    /// wall-clock by rolling forward — instead of silently dropping the
    /// month's occurrence the way a raw `date(from: components)` build can.
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

// MARK: - Recurrence rule model (Reminders-style custom editor)


// MARK: - Building blocks

/// A weekday, numbered to match `Calendar`'s `.weekday` component
/// (1 = Sunday … 7 = Saturday) and mapped to its RFC 5545 BYDAY code.
enum RecurrenceWeekday: Int, CaseIterable, Hashable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var rrule: String { ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][rawValue - 1] }

    /// Localised full name ("Sunday"). `weekdaySymbols` is always Sunday-first.
    var fullName: String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols.indices.contains(rawValue - 1) ? symbols[rawValue - 1] : "\(rawValue)"
    }

    static func from(rrule code: String) -> RecurrenceWeekday? {
        switch code.uppercased() {
        case "SU": return .sunday
        case "MO": return .monday
        case "TU": return .tuesday
        case "WE": return .wednesday
        case "TH": return .thursday
        case "FR": return .friday
        case "SA": return .saturday
        default:   return nil
        }
    }
}

/// The "first / second / … / last" position used by monthly "On the…" and the
/// yearly days-of-week option. Stored as the RFC 5545 ordinal (`last` = -1).
enum RecurrenceOrdinal: Int, CaseIterable, Hashable, Identifiable {
    case first = 1, second, third, fourth, fifth
    case last = -1

    var id: Int { rawValue }

    /// Word form for the picker wheel ("third", "last").
    var word: String {
        switch self {
        case .first:  return "first"
        case .second: return "second"
        case .third:  return "third"
        case .fourth: return "fourth"
        case .fifth:  return "fifth"
        case .last:   return "last"
        }
    }

    /// Short form for the summary sentence ("3rd", "last").
    var shortForm: String {
        self == .last ? "last" : RecurrenceFormat.ordinal(rawValue)
    }

    /// RFC 5545 BYDAY ordinal prefix ("3", "-1").
    var rrulePrefix: String { self == .last ? "-1" : "\(rawValue)" }

    static func from(rrulePrefix raw: Int) -> RecurrenceOrdinal? {
        raw < 0 ? .last : RecurrenceOrdinal(rawValue: raw)
    }
}

// MARK: - The rule

/// Mirrors Apple Reminders' "Custom" recurrence editor. Round-trips to an
/// RFC 5545 RRULE (the string the app stores in `Recurrence.rrule`) and produces
/// the "Event will occur…" summary sentence shown under the controls.
///
/// Fields not relevant to the current `frequency` are still carried (seeded from
/// the start date) so toggling frequency in the editor keeps sensible values.
struct RecurrenceRule: Equatable {
    enum Frequency: String, CaseIterable, Identifiable {
        case hourly, daily, weekly, monthly, yearly

        var id: String { rawValue }
        var rruleValue: String { rawValue.uppercased() }
        var displayName: String {
            switch self {
            case .hourly:  return "Hourly"
            case .daily:   return "Daily"
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            case .yearly:  return "Yearly"
            }
        }
        var unitSingular: String {
            switch self {
            case .hourly:  return "hour"
            case .daily:   return "day"
            case .weekly:  return "week"
            case .monthly: return "month"
            case .yearly:  return "year"
            }
        }
        var unitPlural: String { unitSingular + "s" }
    }

    enum MonthlyMode: Equatable { case each, onThe }

    var frequency: Frequency
    var interval: Int

    /// Weekly: selected weekdays (BYDAY without ordinals). May be empty.
    var weekdays: Set<RecurrenceWeekday>

    /// Monthly: "Each" (calendar grid) vs "On the…" (ordinal + weekday).
    var monthlyMode: MonthlyMode
    var monthDays: Set<Int>            // "Each": days 1…31 (BYMONTHDAY)

    /// Shared by monthly "On the…" and the yearly days-of-week option.
    var ordinal: RecurrenceOrdinal
    var ordinalWeekday: RecurrenceWeekday

    /// Yearly: selected months (BYMONTH) + optional ordinal-weekday refinement.
    var months: Set<Int>              // 1…12
    var yearlyUsesDaysOfWeek: Bool

    // MARK: Seed

    /// A fresh rule seeded from a start date, so Weekly defaults to that
    /// weekday, Monthly to that day, Yearly to that month, etc.
    static func makeDefault(from date: Date = .now, frequency: Frequency = .weekly,
                            calendar: Calendar = .current) -> RecurrenceRule {
        let weekday = RecurrenceWeekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        return RecurrenceRule(
            frequency: frequency,
            interval: 1,
            weekdays: [weekday],
            monthlyMode: .each,
            monthDays: [day],
            ordinal: .first,
            ordinalWeekday: weekday,
            months: [month],
            yearlyUsesDaysOfWeek: false
        )
    }

    // MARK: RRULE generation

    var rrule: String {
        var parts = ["FREQ=\(frequency.rruleValue)"]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }

        switch frequency {
        case .hourly, .daily:
            break
        case .weekly:
            if !weekdays.isEmpty {
                let codes = weekdays.sorted { $0.rawValue < $1.rawValue }.map(\.rrule)
                parts.append("BYDAY=\(codes.joined(separator: ","))")
            }
        case .monthly:
            switch monthlyMode {
            case .each:
                if !monthDays.isEmpty {
                    parts.append("BYMONTHDAY=\(monthDays.sorted().map(String.init).joined(separator: ","))")
                }
            case .onThe:
                parts.append("BYDAY=\(ordinal.rrulePrefix)\(ordinalWeekday.rrule)")
            }
        case .yearly:
            if !months.isEmpty {
                parts.append("BYMONTH=\(months.sorted().map(String.init).joined(separator: ","))")
            }
            if yearlyUsesDaysOfWeek {
                parts.append("BYDAY=\(ordinal.rrulePrefix)\(ordinalWeekday.rrule)")
            }
        }
        return parts.joined(separator: ";")
    }

    // MARK: RRULE parsing

    /// Best-effort parse into the editor model. Returns nil if the FREQ is
    /// missing/unknown. Fields irrelevant to the FREQ are seeded from `date`.
    static func parse(_ rrule: String, date: Date = .now, calendar: Calendar = .current) -> RecurrenceRule? {
        let parts = Dictionary(
            rrule.split(separator: ";").compactMap { part -> (String, String)? in
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0].uppercased(), kv[1]) : nil
            },
            uniquingKeysWith: { _, new in new })

        guard let freqRaw = parts["FREQ"],
              let frequency = Frequency(rawValue: freqRaw.lowercased()) else { return nil }

        var rule = makeDefault(from: date, frequency: frequency, calendar: calendar)
        rule.interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)

        // BYDAY may carry an ordinal prefix (e.g. "2SU", "-1FR") or be a plain
        // weekday list ("TU,TH,SA").
        let bydayTokens = (parts["BYDAY"] ?? "").split(separator: ",").map(String.init)
        let plainWeekdays = bydayTokens.compactMap(RecurrenceWeekday.from(rrule:))
        let ordinalToken = bydayTokens.compactMap(Self.parseOrdinalDay).first

        switch frequency {
        case .hourly, .daily:
            break
        case .weekly:
            if !plainWeekdays.isEmpty { rule.weekdays = Set(plainWeekdays) }
        case .monthly:
            if let days = parts["BYMONTHDAY"] {
                rule.monthlyMode = .each
                let parsed = days.split(separator: ",").compactMap { Int($0) }.filter { (1...31).contains($0) }
                if !parsed.isEmpty { rule.monthDays = Set(parsed) }
            } else if let ord = ordinalToken {
                rule.monthlyMode = .onThe
                rule.ordinal = ord.ordinal
                rule.ordinalWeekday = ord.weekday
            }
        case .yearly:
            if let months = parts["BYMONTH"] {
                let parsed = months.split(separator: ",").compactMap { Int($0) }.filter { (1...12).contains($0) }
                if !parsed.isEmpty { rule.months = Set(parsed) }
            }
            if let ord = ordinalToken {
                rule.yearlyUsesDaysOfWeek = true
                rule.ordinal = ord.ordinal
                rule.ordinalWeekday = ord.weekday
            }
        }
        return rule
    }

    /// Parse a single BYDAY token that includes an ordinal ("2SU", "-1FR").
    /// Returns nil for plain weekday codes.
    private static func parseOrdinalDay(_ token: String) -> (ordinal: RecurrenceOrdinal, weekday: RecurrenceWeekday)? {
        let code = String(token.suffix(2))
        let prefix = String(token.dropLast(2))
        guard !prefix.isEmpty, let n = Int(prefix),
              let weekday = RecurrenceWeekday.from(rrule: code),
              let ordinal = RecurrenceOrdinal.from(rrulePrefix: n) else { return nil }
        return (ordinal, weekday)
    }

    // MARK: Summaries

    /// "every 6 weeks", "every year", "every hour" — the leading clause.
    private var coreClause: String {
        interval == 1
            ? "every \(frequency.unitSingular)"
            : "every \(interval) \(frequency.unitPlural)"
    }

    /// Full sentence shown under the controls in the editor.
    /// e.g. "Event will occur every 6 weeks on Tuesday, Thursday and Saturday."
    var summary: String {
        var sentence = "Event will occur \(coreClause)"
        switch frequency {
        case .hourly, .daily:
            break
        case .weekly:
            if !weekdays.isEmpty {
                let names = weekdays.sorted { $0.rawValue < $1.rawValue }.map(\.fullName)
                sentence += " on \(RecurrenceFormat.list(names))"
            }
        case .monthly:
            switch monthlyMode {
            case .each:
                if !monthDays.isEmpty {
                    let days = monthDays.sorted().map(RecurrenceFormat.ordinal)
                    sentence += " on the \(RecurrenceFormat.list(days))"
                }
            case .onThe:
                sentence += " on the \(ordinal.shortForm) \(ordinalWeekday.fullName)"
            }
        case .yearly:
            if yearlyUsesDaysOfWeek {
                sentence += " on the \(ordinal.shortForm) \(ordinalWeekday.fullName) of \(monthsClause)"
            }
        }
        return sentence + "."
    }

    /// Concise label for the Repeat row / item-row indicator ("Every 6 weeks").
    var shortLabel: String { coreClause.capitalizedFirst }

    private var monthsClause: String {
        let symbols = Calendar.current.monthSymbols
        let names = months.sorted().compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
        return names.isEmpty ? "the year" : RecurrenceFormat.list(names)
    }
}

// MARK: - Formatting helpers

enum RecurrenceFormat {
    /// "1st", "2nd", "23rd" …
    static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// "A", "A and B", "A, B and C" (Apple-style, no Oxford comma).
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
