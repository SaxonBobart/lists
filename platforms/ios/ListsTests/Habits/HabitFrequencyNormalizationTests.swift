import XCTest
@testable import Lists

/// Habits are locked to three cadences — daily, weekly, monthly — so the streak
/// always reads as a day-, week-, or month-streak. Any legacy frequency a stored
/// habit might carry is folded onto one of the three on edit/save.
final class HabitFrequencyNormalizationTests: XCTestCase {

    func testHabitCadencesAreExactlyTheThree() {
        XCTAssertEqual(HabitFrequency.habitCadences, [.daily, .weekly, .monthly])
    }

    func testTheThreeNormalizeToThemselves() {
        XCTAssertEqual(HabitFrequency.daily.normalizedForHabit, .daily)
        XCTAssertEqual(HabitFrequency.weekly.normalizedForHabit, .weekly)
        XCTAssertEqual(HabitFrequency.monthly.normalizedForHabit, .monthly)
    }

    func testSubDailyAndDayFilteredCadencesBecomeDaily() {
        XCTAssertEqual(HabitFrequency.hourly.normalizedForHabit, .daily)
        XCTAssertEqual(HabitFrequency.weekdays.normalizedForHabit, .daily)
        XCTAssertEqual(HabitFrequency.weekends.normalizedForHabit, .daily)
        XCTAssertEqual(HabitFrequency.custom.normalizedForHabit, .daily)
    }

    func testFortnightlyBecomesWeekly() {
        XCTAssertEqual(HabitFrequency.fortnightly.normalizedForHabit, .weekly)
    }

    func testMultiMonthAndYearlyBecomeMonthly() {
        XCTAssertEqual(HabitFrequency.everyThreeMonths.normalizedForHabit, .monthly)
        XCTAssertEqual(HabitFrequency.everySixMonths.normalizedForHabit, .monthly)
        XCTAssertEqual(HabitFrequency.yearly.normalizedForHabit, .monthly)
    }

    func testEveryFrequencyNormalizesIntoTheAllowedSet() {
        for f in HabitFrequency.allCases {
            XCTAssertTrue(HabitFrequency.habitCadences.contains(f.normalizedForHabit),
                          "\(f) normalized to \(f.normalizedForHabit), which is not an allowed habit cadence")
        }
    }
}
