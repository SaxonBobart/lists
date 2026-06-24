import Foundation
import Testing
@testable import Lists

/// Forgiving, consistency-led habit stats. The streak no longer resets on a
/// single missed cycle ("never miss twice" — two consecutive misses break it),
/// and the hero metric is a calm "showed up X of Y" consistency stat rather than
/// the fragile streak number.
struct HabitStatsTests {
    private let now = ISO8601.date(from: "2026-05-20T12:00:00.000Z")!

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    /// A daily habit completed on the given day offsets (0 = today, 1 = yesterday…),
    /// `goal` events per listed day.
    private func dailyHabit(metOffsets: [Int], goal: Int = 1) -> Item {
        var item = Item(type: .habit, title: "H", listId: "inbox",
                        frequency: .daily, goalPerCycle: goal)
        for off in metOffsets {
            let day = utc.date(byAdding: .day, value: -off, to: now)!
            for i in 0..<goal {
                item.completions.append(HabitCompletion(at: day.addingTimeInterval(Double(i))))
            }
        }
        return item
    }

    // MARK: - Forgiving streak

    @Test func consecutiveMetDaysGiveStreak() {
        let item = dailyHabit(metOffsets: [0, 1, 2, 3])
        #expect(HabitStats.streak(for: item, now: now) == 4)
    }

    @Test func singleMissedDayIsForgiven() {
        // met, met, MISS, met, met  → one gap is stepped over.
        let item = dailyHabit(metOffsets: [0, 1, 3, 4])
        #expect(HabitStats.streak(for: item, now: now) == 4)
    }

    @Test func twoConsecutiveMissesBreakTheStreak() {
        // met, met, MISS, MISS, met → breaks at the second miss.
        let item = dailyHabit(metOffsets: [0, 1, 4])
        #expect(HabitStats.streak(for: item, now: now) == 2)
    }

    @Test func incompleteTodayDoesNotBreakTheStreak() {
        // Today not done yet; the prior three days form the streak.
        let item = dailyHabit(metOffsets: [1, 2, 3])
        #expect(HabitStats.streak(for: item, now: now) == 3)
    }

    @Test func noCompletionsHasZeroStreak() {
        #expect(HabitStats.streak(for: dailyHabit(metOffsets: []), now: now) == 0)
    }

    @Test func partialCycleBelowGoalCountsAsAMiss() {
        // goal 2: today=2 (met), yesterday=1 (partial → miss, forgiven), 2-ago=2 (met),
        // 3-ago=0 (miss → second consecutive with nothing before resets).
        var item = Item(type: .habit, title: "H", listId: "inbox",
                        frequency: .daily, goalPerCycle: 2)
        func add(_ off: Int, _ n: Int) {
            let day = utc.date(byAdding: .day, value: -off, to: now)!
            for i in 0..<n { item.completions.append(HabitCompletion(at: day.addingTimeInterval(Double(i)))) }
        }
        add(0, 2); add(1, 1); add(2, 2)
        // today met(1), yesterday partial miss(forgiven), 2-ago met(2), 3-ago miss(break)
        #expect(HabitStats.streak(for: item, now: now) == 2)
    }

    // MARK: - Consistency (hero stat)

    @Test func consistencyCountsMetDaysInWindow() {
        let item = dailyHabit(metOffsets: Array(0...21))  // 22 met days
        let stat = HabitStats.consistency(for: item, days: 30, now: now)
        #expect(stat.shown == 22)
        #expect(stat.window == 30)
        #expect(abs(stat.rate - 22.0 / 30.0) <= 0.0001)
    }

    @Test func consistencyIgnoresDaysOutsideTheWindow() {
        let item = dailyHabit(metOffsets: [40, 50])  // both older than 30 days
        let stat = HabitStats.consistency(for: item, days: 30, now: now)
        #expect(stat.shown == 0)
        #expect(stat.window == 30)
    }

    @Test func legacyWeekdaysFrequencyNormalizesToDaily() {
        // Habits are locked to daily/weekly/monthly; a stored legacy `weekdays`
        // cadence reads as daily everywhere, so all 7 days are scheduled,
        // matching what the detail screen and row show.
        var item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekdays, goalPerCycle: 1)
        for off in 0..<7 {
            let day = utc.date(byAdding: .day, value: -off, to: now)!
            item.completions.append(HabitCompletion(at: day))
        }
        let stat = HabitStats.consistency(for: item, days: 7, now: now)
        #expect(stat.window == 7, "normalized to daily: every day is scheduled")
        #expect(stat.shown == 7)
    }

    // MARK: - Lifetime stats

    @Test func totalCompletionsCountsEveryEvent() {
        let item = dailyHabit(metOffsets: [0, 1], goal: 2)
        #expect(HabitStats.totalCompletions(for: item) == 4)
    }

    @Test func bestStreakFindsLongestForgivingRun() {
        // Run of 5 (offsets 10…6), break (offsets 5,4 missed), recent run of 3 (2,1,0).
        let item = dailyHabit(metOffsets: [10, 9, 8, 7, 6, 2, 1, 0])
        #expect(HabitStats.bestStreak(for: item, now: now) == 5)
        #expect(HabitStats.streak(for: item, now: now) == 3, "current streak is the recent run")
    }

    @Test func completionRateIsMetOverScheduledSinceFirstCompletion() {
        let item = dailyHabit(metOffsets: [10, 9, 8, 7, 6, 2, 1, 0])  // 8 met across 11 days
        #expect(abs(HabitStats.completionRate(for: item, now: now) - 8.0 / 11.0) <= 0.0001)
    }
}
