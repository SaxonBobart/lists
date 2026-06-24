import Foundation

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
        let parts = RRuleParts.parse(rrule)

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
