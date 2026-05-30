import XCTest
@testable import Lists

/// The contribution grid draws one square per cycle (day / week / month).
/// `HabitStats.recentCycles` is the data behind it: the last N cycles up to and
/// including the current one, oldest → newest, each with its completion count.
final class HabitRecentCyclesTests: XCTestCase {

    private let now = ISO8601.date(from: "2026-05-20T12:00:00.000Z")!

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func habit(_ frequency: HabitFrequency, dayOffsets: [Int], goal: Int = 1) -> Item {
        var item = Item(type: .habit, title: "H", listId: "inbox",
                        frequency: frequency, goalPerCycle: goal)
        for off in dayOffsets {
            item.completions.append(HabitCompletion(at: utc.date(byAdding: .day, value: -off, to: now)!))
        }
        return item
    }

    func testDailyGivesOneCellPerDayNewestLast() {
        // completions today, yesterday, 3-days-ago.
        let item = habit(.daily, dayOffsets: [0, 1, 3])
        let cells = HabitStats.recentCycles(for: item, limit: 5, now: now)
        XCTAssertEqual(cells.count, 5)
        // oldest → newest: [4-ago, 3-ago, 2-ago, 1-ago, today]
        XCTAssertEqual(cells.map(\.count), [0, 1, 0, 1, 1])
    }

    func testWeeklyAggregatesCompletionsPerWeek() {
        // two this week (today + yesterday), one last week (7 days ago).
        let item = habit(.weekly, dayOffsets: [0, 1, 7])
        let cells = HabitStats.recentCycles(for: item, limit: 3, now: now)
        XCTAssertEqual(cells.count, 3)
        // [2-weeks-ago, last-week, this-week]
        XCTAssertEqual(cells.map(\.count), [0, 1, 2])
    }

    func testMonthlyAggregatesCompletionsPerMonth() {
        // three this month, one last month.
        let item = habit(.monthly, dayOffsets: [0, 1, 2, 32])
        let cells = HabitStats.recentCycles(for: item, limit: 3, now: now)
        XCTAssertEqual(cells.count, 3)
        // [2-months-ago, last-month, this-month]
        XCTAssertEqual(cells.map(\.count), [0, 1, 3])
    }

    func testLegacyFrequencyIsNormalizedToMonthlyCells() {
        // A stored 'every 3 months' habit must draw monthly cells, not quarters.
        let item = habit(.everyThreeMonths, dayOffsets: [0])
        let cells = HabitStats.recentCycles(for: item, limit: 2, now: now)
        XCTAssertEqual(cells.last?.key, HabitCycle.key(for: .monthly, on: now))
        XCTAssertEqual(cells.last?.count, 1)
    }

    func testEmptyForZeroLimitOrNonHabit() {
        XCTAssertTrue(HabitStats.recentCycles(for: habit(.daily, dayOffsets: [0]), limit: 0, now: now).isEmpty)
        let task = Item(type: .task, title: "T", listId: "inbox")
        XCTAssertTrue(HabitStats.recentCycles(for: task, limit: 5, now: now).isEmpty)
    }
}
