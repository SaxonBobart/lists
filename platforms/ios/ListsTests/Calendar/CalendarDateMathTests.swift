import Foundation
import Testing
@testable import Lists

struct CalendarDateMathTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_AU")
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    @Test func monthGridCoversWholeWeeksAroundTheMonth() {
        let interval = CalendarDateMath.monthGridInterval(
            containing: date(2026, 7, 15),
            calendar: calendar
        )
        let days = CalendarDateMath.days(in: interval, calendar: calendar)

        #expect(interval.start == date(2026, 6, 29))
        #expect(interval.end == date(2026, 8, 3))
        #expect(days.count == 35)
    }

    @Test func threeDayAndWeekRangesAdvanceByTheirVisibleSpan() {
        let anchor = date(2026, 7, 15, 9)
        let threeDays = CalendarDateMath.interval(
            for: .threeDay,
            anchor: anchor,
            calendar: calendar
        )
        let week = CalendarDateMath.interval(
            for: .week,
            anchor: anchor,
            calendar: calendar
        )

        #expect(threeDays.start == date(2026, 7, 15))
        #expect(threeDays.end == date(2026, 7, 18))
        #expect(week.start == date(2026, 7, 13))
        #expect(week.end == date(2026, 7, 20))
        #expect(
            CalendarDateMath.shifted(
                anchor,
                kind: .threeDay,
                direction: 1,
                calendar: calendar
            ) == date(2026, 7, 18, 9)
        )
    }

    @Test func agendaUsesTheNamedMonthWithoutMonthGridSpillover() {
        let interval = CalendarDateMath.interval(
            for: .list,
            anchor: date(2026, 7, 15),
            calendar: calendar
        )

        #expect(interval.start == date(2026, 7, 1))
        #expect(interval.end == date(2026, 8, 1))
    }

    @Test func weekendFilteringPreservesLocaleWeekdayOrder() {
        let monday = date(2026, 7, 13)
        let weekdays = CalendarDateMath.visibleWeekdays(
            from: monday,
            showWeekends: false,
            calendar: calendar
        )

        #expect(weekdays.count == 5)
        #expect(weekdays.first == monday)
        #expect(weekdays.last == date(2026, 7, 17))
    }

    @Test func multiDayEntriesAppearOnEveryCoveredDayButNotAtExclusiveEnd() {
        let start = date(2026, 7, 18)
        let end = date(2026, 7, 20)
        let entry = calendarEntry(start: start, end: end, allDay: true)
        let interval = DateInterval(
            start: date(2026, 7, 13),
            end: date(2026, 7, 27)
        )

        let index = CalendarEntryIndex(
            entries: [entry],
            interval: interval,
            calendar: calendar
        )

        #expect(index.entries(on: date(2026, 7, 18)) == [entry])
        #expect(index.entries(on: date(2026, 7, 19)) == [entry])
        #expect(index.entries(on: date(2026, 7, 20)).isEmpty)
    }

    @Test func entriesAreClippedToTheVisibleInterval() {
        let spanning = calendarEntry(
            start: date(2026, 7, 10),
            end: date(2026, 7, 15),
            allDay: true
        )
        let outside = calendarEntry(
            start: date(2026, 8, 1),
            end: date(2026, 8, 2),
            allDay: true
        )
        let interval = DateInterval(
            start: date(2026, 7, 13),
            end: date(2026, 7, 20)
        )

        let index = CalendarEntryIndex(
            entries: [spanning, outside],
            interval: interval,
            calendar: calendar
        )

        #expect(index.populatedDays == [date(2026, 7, 13), date(2026, 7, 14)])
    }

    @Test func timelineStartsNearNowOnlyWhenShowingToday() {
        let today = date(2026, 7, 15)
        let event = calendarEntry(
            start: date(2026, 7, 15, 9),
            end: date(2026, 7, 15, 10),
            allDay: false
        )

        #expect(CalendarTimelinePolicy.initialHour(
            for: today,
            entries: [event],
            now: date(2026, 7, 15, 15),
            calendar: calendar
        ) == 13)
        #expect(CalendarTimelinePolicy.initialHour(
            for: date(2026, 7, 16),
            entries: [event],
            now: date(2026, 7, 15, 15),
            calendar: calendar
        ) == 7)
    }

    @Test func timelineUsesTheFirstTimedEntryForAnotherDay() {
        let day = date(2026, 7, 16)
        let early = calendarEntry(
            start: date(2026, 7, 16, 7),
            end: date(2026, 7, 16, 8),
            allDay: false
        )
        let later = calendarEntry(
            start: date(2026, 7, 16, 14),
            end: date(2026, 7, 16, 15),
            allDay: false
        )

        #expect(CalendarTimelinePolicy.initialHour(
            for: day,
            entries: [later, early],
            now: date(2026, 7, 15, 15),
            calendar: calendar
        ) == 5)
    }

    @Test func onlyCurrentEventsExposeDurationResize() {
        let event = calendarEntry(
            start: date(2026, 7, 16, 9),
            end: date(2026, 7, 16, 10),
            allDay: false
        )
        let task = calendarEntry(
            start: date(2026, 7, 16, 9),
            end: date(2026, 7, 16, 9),
            allDay: false,
            type: .task
        )
        let projected = calendarEntry(
            start: date(2026, 7, 17, 9),
            end: date(2026, 7, 17, 10),
            allDay: false,
            source: .projected
        )

        #expect(CalendarTimelinePolicy.canResize(event))
        #expect(!CalendarTimelinePolicy.canResize(task))
        #expect(!CalendarTimelinePolicy.canResize(projected))
    }

    private func calendarEntry(
        start: Date,
        end: Date,
        allDay: Bool,
        type: Item.ItemType = .event,
        source: CalendarEntry.ID.Source = .current
    ) -> CalendarEntry {
        let itemId = UUID()
        return CalendarEntry(
            id: .init(
                itemId: itemId,
                source: source,
                scheduledAt: start,
                occurrenceId: nil
            ),
            itemId: itemId,
            title: "Entry",
            type: type,
            listId: "list",
            section: nil,
            start: start,
            end: end,
            isAllDay: allDay,
            status: .open,
            isCompletable: false,
            priority: .none,
            flagged: false,
            hasRecurrence: false
        )
    }
}
