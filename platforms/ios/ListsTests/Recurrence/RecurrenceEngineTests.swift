import XCTest
@testable import Lists

/// TASK-1: pure recurrence expansion. Given a fired date + an RRULE, return the
/// next occurrence (or nil when the rule is unparseable / the series has ended).
final class RecurrenceEngineTests: XCTestCase {

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

    func testDaily() { XCTAssertEqual(next(date(2026, 1, 1), "FREQ=DAILY"), date(2026, 1, 2)) }
    func testDailyInterval() { XCTAssertEqual(next(date(2026, 1, 1), "FREQ=DAILY;INTERVAL=2"), date(2026, 1, 3)) }
    func testWeekly() { XCTAssertEqual(next(date(2026, 1, 1), "FREQ=WEEKLY"), date(2026, 1, 8)) }
    func testMonthly() { XCTAssertEqual(next(date(2026, 1, 1), "FREQ=MONTHLY"), date(2026, 2, 1)) }
    func testYearly() { XCTAssertEqual(next(date(2026, 1, 1), "FREQ=YEARLY"), date(2027, 1, 1)) }
    func testHourly() { XCTAssertEqual(next(date(2026, 1, 1, 9), "FREQ=HOURLY"), date(2026, 1, 1, 10)) }

    // 2026-01-02 is a Friday; 2026-01-06 a Tuesday; 2026-01-04 a Sunday.
    func testWeekdaysFromFridaySkipsToMonday() {
        XCTAssertEqual(next(date(2026, 1, 2), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"), date(2026, 1, 5))
    }
    func testWeekdaysFromTuesdayIsWednesday() {
        XCTAssertEqual(next(date(2026, 1, 6), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"), date(2026, 1, 7))
    }
    func testWeekendsFromSundayIsSaturday() {
        XCTAssertEqual(next(date(2026, 1, 4), "FREQ=WEEKLY;BYDAY=SA,SU"), date(2026, 1, 10))
    }

    func testUntilInPastEndsSeries() {
        XCTAssertNil(next(date(2026, 1, 1), "FREQ=DAILY;UNTIL=20250101T000000Z"))
    }
    func testUntilInFutureReturnsDate() {
        XCTAssertEqual(next(date(2026, 1, 1), "FREQ=DAILY;UNTIL=20270101T000000Z"), date(2026, 1, 2))
    }

    func testGarbageOrMissingFreqReturnsNil() {
        XCTAssertNil(next(date(2026, 1, 1), ""))
        XCTAssertNil(next(date(2026, 1, 1), "INTERVAL=2"))
        XCTAssertNil(next(date(2026, 1, 1), "FREQ=BOGUS"))
    }

    func testTimeOfDayPreserved() {
        let from = date(2026, 1, 1, 9, 30)
        let n = try? XCTUnwrap(next(from, "FREQ=DAILY"))
        XCTAssertEqual(cal.component(.hour, from: n!), 9)
        XCTAssertEqual(cal.component(.minute, from: n!), 30)
    }
}
