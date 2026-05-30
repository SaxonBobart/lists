import XCTest
@testable import Lists

/// Flexible "X times per week/month" habits: a `flexibleGoal` flag re-reads
/// `goalPerCycle` as "N times across the cycle" and drives calm cycle-aware
/// copy ("2 of 3 this week"). The heatmap groups real per-day activity so a
/// weekly habit still shows which days you showed up.
final class HabitFlexibleScheduleTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    // MARK: - flexibleGoal persistence

    func testFlexibleGoalDefaultsFalse() {
        let item = Item(type: .habit, title: "H", listId: "inbox", frequency: .weekly)
        XCTAssertFalse(item.flexibleGoal)
    }

    func testFlexibleGoalRoundTripsWhenTrue() throws {
        var item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekly, goalPerCycle: 3)
        item.flexibleGoal = true
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        XCTAssertTrue(decoded.flexibleGoal)
    }

    func testFlexibleGoalFalseIsNotWritten() throws {
        let item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekly, goalPerCycle: 3)
        XCTAssertFalse(try FrontmatterCodec.encode(item).contains("flexible_goal"))
    }

    // MARK: - cycle copy

    func testCycleNounMatchesFrequency() {
        XCTAssertEqual(HabitStats.cycleNoun(for: .daily), "today")
        XCTAssertEqual(HabitStats.cycleNoun(for: .weekly), "this week")
        XCTAssertEqual(HabitStats.cycleNoun(for: .monthly), "this month")
        XCTAssertEqual(HabitStats.cycleNoun(for: .yearly), "this year")
    }

    // MARK: - per-day heatmap grouping

    func testCompletionsByDayGroupsEventsByCalendarDay() {
        let d1 = ISO8601.date(from: "2026-05-20T09:00:00.000Z")!
        let d1evening = ISO8601.date(from: "2026-05-20T18:00:00.000Z")!
        let d2 = ISO8601.date(from: "2026-05-18T10:00:00.000Z")!

        var item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekly, goalPerCycle: 3)
        item.completions = [HabitCompletion(at: d1), HabitCompletion(at: d1evening),
                            HabitCompletion(at: d2)]

        let byDay = HabitStats.completionsByDay(for: item)
        XCTAssertEqual(byDay["2026-05-20"], 2, "two events on the same day collapse to a count of 2")
        XCTAssertEqual(byDay["2026-05-18"], 1)
        XCTAssertNil(byDay["2026-05-19"], "a day with no events has no entry")
    }
}
