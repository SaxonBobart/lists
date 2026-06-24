import Foundation
import Testing
@testable import Lists

/// Pure recurrence expansion. Given a fired date + an RRULE, return the next
/// occurrence (or nil when the rule is unparseable / the series has ended).
struct RecurrenceEngineTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func next(_ from: Date, _ rrule: String) -> Date? {
        RecurrenceEngine.nextOccurrence(after: from, rrule: rrule, calendar: cal)
    }

    @Test func daily() { #expect(next(date(2026, 1, 1), "FREQ=DAILY") == date(2026, 1, 2)) }
    @Test func dailyInterval() { #expect(next(date(2026, 1, 1), "FREQ=DAILY;INTERVAL=2") == date(2026, 1, 3)) }
    @Test func weekly() { #expect(next(date(2026, 1, 1), "FREQ=WEEKLY") == date(2026, 1, 8)) }
    @Test func monthly() { #expect(next(date(2026, 1, 1), "FREQ=MONTHLY") == date(2026, 2, 1)) }
    @Test func yearly() { #expect(next(date(2026, 1, 1), "FREQ=YEARLY") == date(2027, 1, 1)) }
    @Test func hourly() { #expect(next(date(2026, 1, 1, 9), "FREQ=HOURLY") == date(2026, 1, 1, 10)) }

    // 2026-01-02 is a Friday; 2026-01-06 a Tuesday; 2026-01-04 a Sunday.
    @Test func weekdaysFromFridaySkipsToMonday() {
        #expect(next(date(2026, 1, 2), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR") == date(2026, 1, 5))
    }

    @Test func weekdaysFromTuesdayIsWednesday() {
        #expect(next(date(2026, 1, 6), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR") == date(2026, 1, 7))
    }

    @Test func weekendsFromSundayIsSaturday() {
        #expect(next(date(2026, 1, 4), "FREQ=WEEKLY;BYDAY=SA,SU") == date(2026, 1, 10))
    }

    @Test func untilInPastEndsSeries() {
        #expect(next(date(2026, 1, 1), "FREQ=DAILY;UNTIL=20250101T000000Z") == nil)
    }

    @Test func untilInFutureReturnsDate() {
        #expect(next(date(2026, 1, 1), "FREQ=DAILY;UNTIL=20270101T000000Z") == date(2026, 1, 2))
    }

    // UNTIL is authored as a day, so the last day's occurrence is included even
    // when the occurrence time is after the UNTIL instant.
    @Test func untilIncludesItsOwnDay() {
        #expect(
            next(date(2026, 1, 1, 9), "FREQ=DAILY;UNTIL=20260102T000000Z") == date(2026, 1, 2, 9),
            "Jan 2's 09:00 occurrence survives an UNTIL of Jan 2 midnight"
        )
        #expect(
            next(date(2026, 1, 2, 9), "FREQ=DAILY;UNTIL=20260102T000000Z") == nil,
            "but Jan 3 is past the end day"
        )
    }

    // A date-only UNTIL (imported/hand-edited RRULE) must end the series, not
    // silently parse to nil (= repeat forever).
    @Test func dateOnlyUntilParses() {
        #expect(next(date(2026, 1, 1), "FREQ=DAILY;UNTIL=20260102") == date(2026, 1, 2))
        #expect(next(date(2026, 1, 2), "FREQ=DAILY;UNTIL=20260102") == nil)
    }

    // A monthly occurrence landing in the spring-forward gap (02:30 on
    // 2026-03-08 does not exist in New York) must roll forward within the day,
    // not vanish from the series.
    @Test func springForwardGapDoesNotDropTheOccurrence() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let anchor = ny.date(from: DateComponents(year: 2026, month: 2, day: 8, hour: 2, minute: 30))!
        let occurrence = try #require(
            RecurrenceEngine.nextOccurrence(after: anchor, rrule: "FREQ=MONTHLY;BYMONTHDAY=8", calendar: ny)
        )

        #expect(ny.component(.month, from: occurrence) == 3, "the March occurrence is not skipped")
        #expect(ny.component(.day, from: occurrence) == 8)
        #expect(
            ny.component(.hour, from: occurrence) >= 3,
            "the nonexistent 02:30 resolves forward past the gap"
        )
    }

    @Test func garbageOrMissingFreqReturnsNil() {
        #expect(next(date(2026, 1, 1), "") == nil)
        #expect(next(date(2026, 1, 1), "INTERVAL=2") == nil)
        #expect(next(date(2026, 1, 1), "FREQ=BOGUS") == nil)
    }

    @Test func timeOfDayPreserved() throws {
        let from = date(2026, 1, 1, 9, 30)
        let occurrence = try #require(next(from, "FREQ=DAILY"))

        #expect(cal.component(.hour, from: occurrence) == 9)
        #expect(cal.component(.minute, from: occurrence) == 30)
    }

    // The calendar used for expansion is pinned to the task's stored zone.
    @Test func calendarForTimeZoneUsesIdentifier() {
        #expect(
            RecurrenceEngine.calendar(forTimeZone: "America/New_York").timeZone == TimeZone(identifier: "America/New_York")
        )
    }

    @Test func calendarForNilTimeZoneFallsBackToCurrent() {
        #expect(RecurrenceEngine.calendar(forTimeZone: nil).timeZone == Calendar.current.timeZone)
    }

    @Test func calendarForUnknownTimeZoneFallsBackToCurrent() {
        #expect(RecurrenceEngine.calendar(forTimeZone: "Not/AZone").timeZone == Calendar.current.timeZone)
    }
}
