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

    @Test func twoDayAndWeekRangesAdvanceByTheirVisibleSpan() {
        let anchor = date(2026, 7, 15, 9)
        let twoDays = CalendarDateMath.interval(
            for: .twoDay,
            anchor: anchor,
            calendar: calendar
        )
        let week = CalendarDateMath.interval(
            for: .week,
            anchor: anchor,
            calendar: calendar
        )

        #expect(twoDays.start == date(2026, 7, 15))
        #expect(twoDays.end == date(2026, 7, 17))
        #expect(week.start == date(2026, 7, 13))
        #expect(week.end == date(2026, 7, 20))
        #expect(
            CalendarDateMath.shifted(
                anchor,
                kind: .twoDay,
                direction: 1,
                calendar: calendar
            ) == date(2026, 7, 17, 9)
        )
    }

    @Test func agendaWindowsExpandSixMonthsAtATime() {
        let initial = CalendarDateMath.agendaWindow(
            centeredOn: date(2026, 7, 15),
            calendar: calendar
        )
        let past = CalendarDateMath.expandingAgendaWindow(
            initial,
            towardPast: true,
            calendar: calendar
        )
        let future = CalendarDateMath.expandingAgendaWindow(
            initial,
            towardPast: false,
            calendar: calendar
        )

        #expect(initial.start == date(2026, 1, 15))
        #expect(initial.end == date(2027, 1, 15))
        #expect(past.start == date(2025, 7, 15))
        #expect(past.end == initial.end)
        #expect(future.start == initial.start)
        #expect(future.end == date(2027, 7, 15))
    }

    @Test func agendaNavigationSkipsEmptyDaysWithoutBlankPlaceholders() {
        let days = [date(2026, 7, 10), date(2026, 7, 20)]
        #expect(CalendarDateMath.agendaScrollDay(target: date(2026, 7, 15), availableDays: days, calendar: calendar) == days[1])
        #expect(CalendarDateMath.agendaScrollDay(target: date(2026, 7, 10, 12), availableDays: days, calendar: calendar) == days[0])
        #expect(CalendarDateMath.agendaScrollDay(target: date(2026, 7, 25), availableDays: days, calendar: calendar) == days[1])
        #expect(CalendarDateMath.agendaScrollDay(target: date(2026, 7, 15), availableDays: [], calendar: calendar) == nil)
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

    @Test func timelineGestureMathSnapsAndEnforcesMinimumDuration() {
        #expect(CalendarTimelinePolicy.snappedMinuteDelta(for: 17, hourHeight: 64) == 15)
        #expect(CalendarTimelinePolicy.snappedMinuteDelta(for: -17, hourHeight: 64) == -15)
        #expect(CalendarTimelinePolicy.clampedStartDelta(60, durationMinutes: 60) == 45)
        #expect(CalendarTimelinePolicy.clampedEndDelta(-60, durationMinutes: 60) == -45)
        #expect(CalendarTimelinePolicy.clampedEndDelta(30, durationMinutes: 60) == 30)
    }

    @Test func overlappingEventsAndDeadlineMarkersHaveSeparateColumns() {
        let first = calendarEntry(start: date(2026, 7, 16, 9), end: date(2026, 7, 16, 11), allDay: false)
        let second = calendarEntry(start: date(2026, 7, 16, 10), end: date(2026, 7, 16, 11), allDay: false)
        let deadline = calendarEntry(start: date(2026, 7, 16, 10), end: date(2026, 7, 16, 10), allDay: false, type: .task)
        let later = calendarEntry(start: date(2026, 7, 16, 11), end: date(2026, 7, 16, 12), allDay: false)
        let placements = CalendarTimelinePolicy.placements(entries: [later, second, deadline, first])
        let concurrent = placements.filter { $0.entry.id != later.id }
        #expect(Set(concurrent.map(\.column)).count == 3)
        #expect(concurrent.allSatisfy { $0.columnCount == 3 })
        #expect(placements.last?.columnCount == 1)
        #expect(deadline.end == deadline.start)
    }

    @Test func movingAcrossMidnightPreservesDuration() {
        let entry = calendarEntry(start: date(2026, 7, 16, 23), end: date(2026, 7, 17, 1), allDay: false)
        let moved = CalendarTimelinePolicy.movedInterval(entry, minutes: 120, calendar: calendar)
        #expect(moved.start == date(2026, 7, 17, 1))
        #expect(moved.end == date(2026, 7, 17, 3))
        let earlier = CalendarTimelinePolicy.movedInterval(entry, minutes: -1440, calendar: calendar)
        #expect(earlier.start == date(2026, 7, 15, 23))
        #expect(earlier.duration == moved.duration)
    }

    @Test func daylightSavingGridUsesClockHoursRatherThanElapsedHours() throws {
        var local = calendar
        local.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        for components in [DateComponents(year: 2026, month: 3, day: 8), DateComponents(year: 2026, month: 11, day: 1)] {
            let day = try #require(local.date(from: components))
            let nine = CalendarTimelinePolicy.date(on: day, minute: 9 * 60, calendar: local)
            #expect(local.component(.hour, from: nine) == 9)
            #expect(CalendarTimelinePolicy.wallMinute(nine, on: day, calendar: local) == 9 * 60)
            let entry = calendarEntry(start: nine, end: nine.addingTimeInterval(3600), allDay: false)
            let moved = CalendarTimelinePolicy.movedInterval(entry, minutes: 60, calendar: local)
            #expect(local.component(.hour, from: moved.start) == 10)
            #expect(moved.duration == 3600)
        }
    }

    @Test func zeroMovementPreservesAnOrdinarySchedule() {
        let entry = calendarEntry(start: date(2026, 7, 16, 9), end: date(2026, 7, 16, 10), allDay: false)
        let unchanged = CalendarTimelinePolicy.movedInterval(entry, minutes: 0, calendar: calendar)
        #expect(unchanged.start == entry.start)
        #expect(unchanged.end == entry.end)
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
