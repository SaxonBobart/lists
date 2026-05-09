import Foundation

/// Maps a habit's `frequency` + a date to a stable cycle-key string. The key
/// goes into `Item.completionLog`. Format per PRODUCT-SPEC.md §3.2.1.
public enum HabitCycle {

    private static let yearMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let yearMonth: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let yearOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy"
        return f
    }()

    public static func key(for frequency: HabitFrequency, on date: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        switch frequency {
        case .hourly:
            let hour = cal.component(.hour, from: date)
            let day = yearMonthDay.string(from: date)
            return "\(day)T\(String(format: "%02d", hour)):00"
        case .daily, .weekdays, .weekends:
            return yearMonthDay.string(from: date)
        case .weekly, .fortnightly:
            let year = cal.component(.yearForWeekOfYear, from: date)
            let week = cal.component(.weekOfYear, from: date)
            return "\(year)-W\(String(format: "%02d", week))"
        case .monthly:
            return yearMonth.string(from: date)
        case .everyThreeMonths:
            let year = cal.component(.year, from: date)
            let month = cal.component(.month, from: date)
            let q = ((month - 1) / 3) + 1
            return "\(year)-Q\(q)"
        case .everySixMonths:
            let year = cal.component(.year, from: date)
            let month = cal.component(.month, from: date)
            let half = month <= 6 ? 1 : 2
            return "\(year)-H\(half)"
        case .yearly:
            return yearOnly.string(from: date)
        case .custom:
            return yearMonthDay.string(from: date)
        }
    }
}

/// Lightweight stats helper read from a habit's completionLog.
public enum HabitStats {

    /// Current consecutive completed cycles ending at `now`. Partial cycles
    /// (count > 0 but < goal) break the streak per spec §3.2.3.
    public static func streak(for item: Item, now: Date = .now) -> Int {
        guard item.type == .habit else { return 0 }
        let frequency = item.frequency ?? .daily
        let goal = item.goalPerCycle
        let cal = Calendar(identifier: .iso8601)

        var count = 0
        var cursor = now
        // Walk backwards through the cycles that frequency defines.
        while count < 3650 {
            let key = HabitCycle.key(for: frequency, on: cursor)
            let cycleCount = item.completionLog[key] ?? 0
            if cycleCount >= goal {
                count += 1
                cursor = previousCycleStart(of: frequency, before: cursor, calendar: cal)
            } else {
                break
            }
        }
        return count
    }

    /// Total cycles in completionLog where count >= goal.
    public static func completedCycles(for item: Item) -> Int {
        guard item.type == .habit else { return 0 }
        let goal = item.goalPerCycle
        return item.completionLog.values.filter { $0 >= goal }.count
    }

    private static func previousCycleStart(
        of frequency: HabitFrequency,
        before date: Date,
        calendar: Calendar
    ) -> Date {
        let comp: Calendar.Component
        let value: Int
        switch frequency {
        case .hourly:           comp = .hour;   value = -1
        case .daily, .custom,
             .weekdays, .weekends: comp = .day;   value = -1
        case .weekly:           comp = .weekOfYear; value = -1
        case .fortnightly:      comp = .weekOfYear; value = -2
        case .monthly:          comp = .month;  value = -1
        case .everyThreeMonths: comp = .month;  value = -3
        case .everySixMonths:   comp = .month;  value = -6
        case .yearly:           comp = .year;   value = -1
        }
        return calendar.date(byAdding: comp, value: value, to: date) ?? date
    }
}
