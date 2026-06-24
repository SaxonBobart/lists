import Foundation
import Testing
@testable import Lists

struct ScheduleFormattingTests {
    @Test func untilRoundTripUsesUtcTimestampForm() {
        let date = ISO8601.date(from: "2026-05-20T09:30:00.000Z")!

        let encoded = ScheduleFormatting.formatUntil(date)

        #expect(encoded == "20260520T093000Z")
        #expect(ScheduleFormatting.parseUntil(encoded) == date)
    }

    @Test func dateOnlyUntilParsesAsLocalDay() throws {
        let parsed = try #require(ScheduleFormatting.parseUntil("20260520"))
        let components = Calendar.current.dateComponents([.year, .month, .day], from: parsed)

        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 20)
    }

    @Test func floatingUntilParsesInProvidedCalendarTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let parsed = try #require(ScheduleFormatting.parseUntil("20260520T093000", calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)

        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 20)
        #expect(components.hour == 9)
        #expect(components.minute == 30)
    }

    @Test func defaultEndRepeatIsSixMonthsFromStartOfToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601.date(from: "2026-06-23T18:45:00.000Z")!

        let end = ScheduleFormatting.defaultEndRepeat(now: now, calendar: calendar)

        #expect(ISO8601.dayString(from: end) == "2026-12-23")
    }

    @Test func customEarlyReminderDisplayHandlesSingularAndPluralUnits() {
        #expect(CustomEarlyReminder.displayName(for: nil) == "Custom…")
        #expect(CustomEarlyReminder.displayName(for: EarlyReminder(value: 1, unit: .hour)) == "1 hour before")
        #expect(CustomEarlyReminder.displayName(for: EarlyReminder(value: 2, unit: .day)) == "2 days before")
    }

    @Test func timeZoneLabelUsesLastIdentifierComponent() {
        #expect(TimeZoneLabel.display(for: "America/New_York") == "New York")
        #expect(TimeZoneLabel.display(for: "UTC") == "UTC")
    }
}
