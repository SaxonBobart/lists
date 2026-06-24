import Testing
@testable import Lists

/// Habits are locked to three cadences — daily, weekly, monthly — so the streak
/// always reads as a day-, week-, or month-streak. Any legacy frequency a stored
/// habit might carry is folded onto one of the three on edit/save.
struct HabitFrequencyNormalizationTests {
    @Test func habitCadencesAreExactlyTheThree() {
        #expect(HabitFrequency.habitCadences == [.daily, .weekly, .monthly])
    }

    @Test func theThreeNormalizeToThemselves() {
        #expect(HabitFrequency.daily.normalizedForHabit == .daily)
        #expect(HabitFrequency.weekly.normalizedForHabit == .weekly)
        #expect(HabitFrequency.monthly.normalizedForHabit == .monthly)
    }

    @Test func subDailyAndDayFilteredCadencesBecomeDaily() {
        #expect(HabitFrequency.hourly.normalizedForHabit == .daily)
        #expect(HabitFrequency.weekdays.normalizedForHabit == .daily)
        #expect(HabitFrequency.weekends.normalizedForHabit == .daily)
        #expect(HabitFrequency.custom.normalizedForHabit == .daily)
    }

    @Test func fortnightlyBecomesWeekly() {
        #expect(HabitFrequency.fortnightly.normalizedForHabit == .weekly)
    }

    @Test func multiMonthAndYearlyBecomeMonthly() {
        #expect(HabitFrequency.everyThreeMonths.normalizedForHabit == .monthly)
        #expect(HabitFrequency.everySixMonths.normalizedForHabit == .monthly)
        #expect(HabitFrequency.yearly.normalizedForHabit == .monthly)
    }

    @Test func everyFrequencyNormalizesIntoTheAllowedSet() {
        for f in HabitFrequency.allCases {
            #expect(
                HabitFrequency.habitCadences.contains(f.normalizedForHabit),
                "\(f) normalized to \(f.normalizedForHabit), which is not an allowed habit cadence"
            )
        }
    }
}
