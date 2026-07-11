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
        // Pinned to UTC so the week/quarter/half component math agrees with
        // the UTC day/month/year formatters above. The same completion instant
        // must never change cycle because the device moved to a different
        // timezone.
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
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

/// A calm "showed up X of Y" summary over a recent window. `rate` is the
/// fraction the UI leads with instead of a fragile streak count.
public struct ConsistencyStat: Equatable, Sendable {
    public let shown: Int
    public let window: Int
    public var rate: Double { window == 0 ? 0 : Double(shown) / Double(window) }
    public init(shown: Int, window: Int) {
        self.shown = shown
        self.window = window
    }
}

/// Forgiving, consistency-led stats derived from a habit's timestamped
/// `completions`. The streak tolerates a single missed cycle ("never miss
/// twice"); two consecutive misses break it.
///
/// Every entry point works on the habit's *normalized* cadence (daily / weekly /
/// monthly) — the same basis `Item.completionLog`, `isComplete`, and the detail
/// screen use — so no two surfaces can ever bucket the same completions
/// differently.
public enum HabitStats {

    /// A stable UTC calendar so cycle stepping matches `HabitCycle.key`'s
    /// day/month/year formatters (which are UTC); week/quarter deltas are
    /// timezone-agnostic in magnitude, and every count is keyed back through
    /// `HabitCycle.key` regardless.
    private static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    /// Completions a single cycle needs to count toward the streak. A
    /// flexible-goal habit keeps its streak alive by showing up just once per
    /// cycle; a fixed-goal habit must reach the full per-cycle goal.
    private static func streakThreshold(for item: Item) -> Int {
        item.flexibleGoal ? 1 : max(1, item.goalPerCycle)
    }

    /// Current streak under the "never miss twice" rule: a single missed cycle
    /// is stepped over; two consecutive misses end it. The in-progress current
    /// cycle neither counts nor penalizes (you still have time to complete it).
    public static func streak(for item: Item, now: Date = .now) -> Int {
        guard item.type == .habit, let frequency = item.frequency?.normalizedForHabit else { return 0 }
        let goal = streakThreshold(for: item)
        let log = item.completionLog
        let cal = calendar

        var streak = 0
        var consecutiveMisses = 0
        var cursor = now
        var isCurrentCycle = true
        var steps = 0
        while steps < 3650 {
            steps += 1
            let met = (log[HabitCycle.key(for: frequency, on: cursor)] ?? 0) >= goal
            if met {
                streak += 1
                consecutiveMisses = 0
            } else if !isCurrentCycle {
                consecutiveMisses += 1
                if consecutiveMisses >= 2 { break }
            }
            isCurrentCycle = false
            cursor = previousCycleStart(of: frequency, before: cursor, calendar: cal)
        }
        return streak
    }

    /// "Showed up X of Y" over the last `days` calendar days: Y is the number of
    /// *scheduled* cycles touching that window (weekends excluded for a weekday
    /// habit, etc.), X the number of those met. The hero stat.
    public static func consistency(for item: Item, days: Int = 30, now: Date = .now) -> ConsistencyStat {
        guard item.type == .habit, let frequency = item.frequency?.normalizedForHabit, days > 0 else {
            return ConsistencyStat(shown: 0, window: 0)
        }
        let goal = item.goalPerCycle
        let log = item.completionLog
        let cal = calendar
        var seen = Set<String>()
        var shown = 0, window = 0
        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: now),
                  isScheduled(frequency, on: date, calendar: cal) else { continue }
            let key = HabitCycle.key(for: frequency, on: date)
            guard seen.insert(key).inserted else { continue }
            window += 1
            if (log[key] ?? 0) >= goal { shown += 1 }
        }
        return ConsistencyStat(shown: shown, window: window)
    }

    /// Every logged completion event, lifetime.
    public static func totalCompletions(for item: Item) -> Int {
        guard item.type == .habit else { return 0 }
        return item.completions.count
    }

    /// The last `limit` cycles up to and including the one containing `now`,
    /// ordered oldest → newest, each with its completion count. The cadence is
    /// normalized (daily / weekly / monthly), and counts are grouped directly off
    /// the events through the normalized key — so a legacy 'every 3 months' habit
    /// draws monthly cells, not quarters. This is the per-cycle contribution grid.
    public static func recentCycles(
        for item: Item,
        limit: Int,
        now: Date = .now
    ) -> [(start: Date, key: String, count: Int)] {
        guard item.type == .habit, limit > 0 else { return [] }
        let freq = (item.frequency ?? .daily).normalizedForHabit
        let cal = calendar
        let counts = Dictionary(grouping: item.completions, by: { HabitCycle.key(for: freq, on: $0.at) })
            .mapValues(\.count)

        var anchors: [Date] = []
        var cursor = now
        for _ in 0..<limit {
            anchors.append(cursor)
            let prev = previousCycleStart(of: freq, before: cursor, calendar: cal)
            if prev >= cursor { break }
            cursor = prev
        }
        return anchors.reversed().map { date in
            let key = HabitCycle.key(for: freq, on: date)
            return (start: date, key: key, count: counts[key] ?? 0)
        }
    }

    /// Calm cycle-relative noun for progress copy, e.g. "of 3 **this week**".
    public static func cycleNoun(for frequency: HabitFrequency) -> String {
        switch frequency {
        case .hourly:           return "this hour"
        case .daily, .custom,
             .weekdays, .weekends: return "today"
        case .weekly:           return "this week"
        case .fortnightly:      return "this fortnight"
        case .monthly:          return "this month"
        case .everyThreeMonths: return "this quarter"
        case .everySixMonths:   return "this half-year"
        case .yearly:           return "this year"
        }
    }

    /// Longest run in the habit's history under the same "never miss twice" rule.
    public static func bestStreak(for item: Item, now: Date = .now) -> Int {
        guard item.type == .habit, let frequency = item.frequency?.normalizedForHabit,
              let earliest = item.completions.map(\.at).min() else { return 0 }
        let goal = streakThreshold(for: item)
        let log = item.completionLog
        let cal = calendar
        let earliestKey = HabitCycle.key(for: frequency, on: earliest)

        // Collect cycles from now back to the earliest completion, chronological.
        var cursors: [Date] = []
        var cursor = now
        var steps = 0
        while steps < 3650 {
            steps += 1
            cursors.append(cursor)
            if HabitCycle.key(for: frequency, on: cursor) == earliestKey { break }
            let prev = previousCycleStart(of: frequency, before: cursor, calendar: cal)
            if prev >= cursor { break }
            cursor = prev
        }

        var best = 0, run = 0, misses = 0
        for c in cursors.reversed() {
            let met = (log[HabitCycle.key(for: frequency, on: c)] ?? 0) >= goal
            if met {
                run += 1
                best = max(best, run)
                misses = 0
            } else {
                misses += 1
                if misses >= 2 { run = 0; misses = 0 }
            }
        }
        return best
    }

    /// Met scheduled cycles ÷ total scheduled cycles since the first completion.
    public static func completionRate(for item: Item, now: Date = .now) -> Double {
        guard item.type == .habit, let frequency = item.frequency?.normalizedForHabit,
              let earliest = item.completions.map(\.at).min() else { return 0 }
        let goal = item.goalPerCycle
        let log = item.completionLog
        let cal = calendar
        let earliestKey = HabitCycle.key(for: frequency, on: earliest)

        var seen = Set<String>()
        var met = 0, total = 0
        var cursor = now
        var steps = 0
        while steps < 3650 {
            steps += 1
            if isScheduled(frequency, on: cursor, calendar: cal) {
                let key = HabitCycle.key(for: frequency, on: cursor)
                if seen.insert(key).inserted {
                    total += 1
                    if (log[key] ?? 0) >= goal { met += 1 }
                }
            }
            if HabitCycle.key(for: frequency, on: cursor) == earliestKey { break }
            let prev = previousCycleStart(of: frequency, before: cursor, calendar: cal)
            if prev >= cursor { break }
            cursor = prev
        }
        return total == 0 ? 0 : Double(met) / Double(total)
    }

    /// Whether `date` is a scheduled cycle for the habit. Only `weekdays` /
    /// `weekends` constrain which days count; all other frequencies treat every
    /// cycle as scheduled.
    private static func isScheduled(_ frequency: HabitFrequency, on date: Date, calendar: Calendar) -> Bool {
        switch frequency {
        case .weekdays:
            return (2...6).contains(calendar.component(.weekday, from: date))
        case .weekends:
            let wd = calendar.component(.weekday, from: date)
            return wd == 1 || wd == 7
        default:
            return true
        }
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
