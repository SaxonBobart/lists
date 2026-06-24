import Foundation
import Testing
@testable import Lists

/// Flexible "X times per week/month" habits: a `flexibleGoal` flag re-reads
/// `goalPerCycle` as "N times across the cycle" and drives calm cycle-aware
/// copy ("2 of 3 this week"). The heatmap groups real per-day activity so a
/// weekly habit still shows which days you showed up.
struct HabitFlexibleScheduleTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    // MARK: - flexibleGoal persistence

    @Test func flexibleGoalDefaultsFalse() {
        let item = Item(type: .habit, title: "H", listId: "inbox", frequency: .weekly)
        #expect(!item.flexibleGoal)
    }

    @Test func flexibleGoalRoundTripsWhenTrue() throws {
        var item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekly, goalPerCycle: 3)
        item.flexibleGoal = true
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        #expect(decoded.flexibleGoal)
    }

    @Test func flexibleGoalFalseIsNotWritten() throws {
        let item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekly, goalPerCycle: 3)
        let encoded = try FrontmatterCodec.encode(item)
        #expect(!encoded.contains("flexible_goal"))
    }

    // MARK: - cycle copy

    @Test func cycleNounMatchesFrequency() {
        #expect(HabitStats.cycleNoun(for: .daily) == "today")
        #expect(HabitStats.cycleNoun(for: .weekly) == "this week")
        #expect(HabitStats.cycleNoun(for: .monthly) == "this month")
        #expect(HabitStats.cycleNoun(for: .yearly) == "this year")
    }

    // MARK: - per-day heatmap grouping

    @Test func completionsByDayGroupsEventsByCalendarDay() {
        let d1 = ISO8601.date(from: "2026-05-20T09:00:00.000Z")!
        let d1evening = ISO8601.date(from: "2026-05-20T18:00:00.000Z")!
        let d2 = ISO8601.date(from: "2026-05-18T10:00:00.000Z")!

        var item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekly, goalPerCycle: 3)
        item.completions = [HabitCompletion(at: d1), HabitCompletion(at: d1evening),
                            HabitCompletion(at: d2)]

        let byDay = HabitStats.completionsByDay(for: item)
        #expect(byDay["2026-05-20"] == 2, "two events on the same day collapse to a count of 2")
        #expect(byDay["2026-05-18"] == 1)
        #expect(byDay["2026-05-19"] == nil, "a day with no events has no entry")
    }
}
