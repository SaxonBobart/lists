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

    @Test func shortSwipesCommitAndWeekMotionRebasesWithoutJumping() {
        #expect(CalendarTimelineGeometry.destination(progress: 12.0 / 350, velocity: 0, columnWidth: 350) == 0)
        #expect(CalendarTimelineGeometry.destination(progress: 35.0 / 350, velocity: 0, columnWidth: 350) == 1)
        #expect(CalendarTimelineGeometry.destination(progress: -35.0 / 350, velocity: 0, columnWidth: 350) == -1)
        for day in [11, 12, 13, 14] {
            for direction in [-8, -3, -1, 1, 3, 8] {
                let selected = date(2026, 9, day)
                let visible = [selected, date(2026, 9, day + 1)]
                let end = CalendarDateMath.weekStripMotion(selected: selected, visible: visible,
                    progress: Double(direction), showWeekends: true, calendar: calendar)
                let next = CalendarDateMath.weekStripMotion(selected: date(2026, 9, day + direction),
                    visible: [date(2026, 9, day + direction), date(2026, 9, day + direction + 1)],
                    progress: 0, showWeekends: true, calendar: calendar)
                #expect(end.selected - end.viewport == next.selected)
                #expect(end.first - end.viewport == next.first)
                #expect(end.last - end.viewport == next.last)
            }
        }
    }

    @Test func pagingNeighborsPreserveFilteredDaysAndColumnContinuity() {
        let days = [7, 8, 9, 10, 11, 14, 15, 16].map { date(2026, 9, $0) }
        #expect(CalendarTimelineGeometry.neighboringDays(in: days, start: 2, columns: 2, page: -1) == Array(days[0..<2]))
        #expect(CalendarTimelineGeometry.neighboringDays(in: days, start: 2, columns: 2, page: 1) == [date(2026, 9, 11), date(2026, 9, 14)])
        let next = CalendarTimelineGeometry.pageOffset(current: 2, direction: 1, columns: 2, count: days.count, editing: false)
        #expect(Array(days[next..<(next + 2)]) == [date(2026, 9, 10), date(2026, 9, 11)])
        #expect(CalendarTimelineGeometry.neighboringDays(in: days, start: 0, columns: 2, page: -1).isEmpty)
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

    @Test func midnightContinuationsAndSimultaneousEventsHaveSeparateTitleSpace() throws {
        let day = date(2026, 9, 8)
        for earlierStart in [date(2026, 9, 7, 23), day] {
            let early = calendarEntry(start: earlierStart, end: date(2026, 9, 8, 7), allDay: false)
            let other = calendarEntry(start: day, end: date(2026, 9, 8, 3), allDay: false)
            let index = CalendarEntryIndex(entries: [early, other],
                interval: DateInterval(start: day, end: date(2026, 9, 9)), calendar: calendar)
            let targets = CalendarTimelineGeometry.targets(days: [day], index: index, width: 393, calendar: calendar)
            #expect(targets.count == 2)
            let first = try #require(targets.first)
            let last = try #require(targets.last)
            #expect(first.frame.minY == last.frame.minY)
            #expect(first.frame.maxX < last.frame.minX)
        }
    }

    @Test func staggeredOverlapsKeepTheirWidthAndLaterCardsAreInset() throws {
        let day = date(2026, 9, 11)
        let early = calendarEntry(start: day, end: date(2026, 9, 11, 4), allDay: false)
        let later = calendarEntry(start: date(2026, 9, 11, 2).addingTimeInterval(45 * 60),
            end: date(2026, 9, 11, 13), allDay: false)
        let index = CalendarEntryIndex(entries: [early, later],
            interval: DateInterval(start: day, end: date(2026, 9, 12)), calendar: calendar)
        let targets = CalendarTimelineGeometry.targets(days: [day], index: index, width: 393, calendar: calendar)
        #expect(targets.count == 2)
        let first = try #require(targets.first)
        let last = try #require(targets.last)
        #expect(last.frame.minX == first.frame.minX + 10)
        #expect(last.frame.maxX == first.frame.maxX)
        #expect(last.frame.width > 300)
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

    @Test func timelineInsetHasOneCoordinateOrigin() {
        #expect(CalendarTimelineGeometry.y(minute: 0) == 18)
        #expect(CalendarTimelineGeometry.minute(y: 18) == 0)
        #expect(CalendarTimelineGeometry.minute(y: 82) == 60)
        #expect(CalendarTimelineGeometry.snapped(67) == 60)
        #expect(CalendarTimelineGeometry.snapped(68) == 75)
    }

    @Test func continuousResizeKeepsHandleAtFingerButSnapsDates() throws {
        let day = date(2026, 9, 8)
        let entry = calendarEntry(start: date(2026, 9, 8, 9), end: date(2026, 9, 8, 10), allDay: false)
        let target = CalendarTimelineTarget(entry: entry, day: day,
            frame: CGRect(x: 59, y: CalendarTimelineGeometry.y(minute: 540), width: 160, height: 64))
        let origin = CGPoint(x: 74, y: target.frame.maxY)
        let gesture = CalendarTimelineGesture(mode: .end, target: target, origin: origin,
            location: CGPoint(x: origin.x, y: origin.y + 11))
        let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day], width: 393, calendar: calendar))
        #expect(preview.frame.maxY == origin.y + 11)
        #expect(preview.end == entry.end.addingTimeInterval(15 * 60))
        #expect(entry.end == date(2026, 9, 8, 10))
    }

    @Test func selectedHandlesTakePriorityOverBodyAndIncludeOutsideEdges() {
        let day = date(2026, 9, 8)
        let entry = calendarEntry(start: date(2026, 9, 8, 9), end: date(2026, 9, 8, 10), allDay: false)
        let target = CalendarTimelineTarget(entry: entry, day: day,
            frame: CGRect(x: 59, y: 500, width: 160, height: 64))
        #expect(CalendarTimelineGeometry.selectedMode(at: CGPoint(x: 204, y: 500), target: target) == .start)
        #expect(CalendarTimelineGeometry.selectedMode(at: CGPoint(x: 74, y: 564), target: target) == .end)
        #expect(CalendarTimelineGeometry.selectedMode(at: CGPoint(x: 74, y: 580), target: target) == .end)
        #expect(CalendarTimelineGeometry.selectedMode(at: CGPoint(x: 140, y: 532), target: target) == .move)
        #expect(CalendarTimelineGeometry.selectedMode(at: CGPoint(x: 250, y: 532), target: target) == nil)
    }

    @Test func dragCrossesDayColumnsAndPreservesDuration() throws {
        let day = date(2026, 9, 8)
        let next = date(2026, 9, 9)
        let entry = calendarEntry(start: date(2026, 9, 8, 9), end: date(2026, 9, 8, 11), allDay: false)
        let target = CalendarTimelineTarget(entry: entry, day: day,
            frame: CGRect(x: 59, y: CalendarTimelineGeometry.y(minute: 540), width: 160, height: 128))
        let origin = CGPoint(x: 100, y: target.frame.minY + 20)
        let gesture = CalendarTimelineGesture(mode: .move, target: target, origin: origin,
            location: CGPoint(x: 280, y: origin.y + 64))
        let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day, next], width: 393, calendar: calendar))
        #expect(preview.day == next)
        #expect(preview.start == date(2026, 9, 9, 10))
        #expect(preview.end == date(2026, 9, 9, 12))
        #expect(preview.frame.minX == 239)
    }

    @Test func pagingMomentumCancellationAndAdaptiveWidths() {
        #expect(CalendarTimelineGeometry.destination(progress: 0.02, velocity: 0, columnWidth: 180) == 0)
        #expect(CalendarTimelineGeometry.destination(progress: 0.7, velocity: -2500, columnWidth: 180) == 3)
        #expect(CalendarTimelineGeometry.destination(progress: -0.7, velocity: 2500, columnWidth: 180) == -3)
        #expect(CalendarTimelineGeometry.adaptiveColumns(width: 393) == 2)
        #expect(CalendarTimelineGeometry.adaptiveColumns(width: 768) == 4)
        #expect(CalendarTimelineGeometry.adaptiveColumns(width: 1024) == 5)
        #expect(CalendarTimelineGeometry.adaptiveColumns(width: 1366) == 7)
    }

    @Test func creationUsesTouchedTimeAfterInsetAndClampsDayEdges() throws {
        let day = date(2026, 9, 8)
        let gesture = CalendarTimelineGesture(mode: .create, target: nil, origin: .zero,
            location: CGPoint(x: 120, y: CalendarTimelineGeometry.y(minute: 577)))
        let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day], width: 393, calendar: calendar))
        #expect(preview.start == date(2026, 9, 8, 9))
        #expect(preview.end.timeIntervalSince(preview.start) == 3600)
        #expect(abs(preview.frame.midY - gesture.location.y) < 0.001)
        #expect(CalendarTimelineGeometry.column(x: -30, width: 393, count: 2) == 0)
        #expect(CalendarTimelineGeometry.column(x: 800, width: 393, count: 2) == 1)
        #expect(CalendarTimelineGeometry.edgeDirection(x: 60, width: 393) == -1)
        #expect(CalendarTimelineGeometry.edgeDirection(x: 385, width: 393) == 1)
        #expect(CalendarTimelineGeometry.edgeDirection(x: 200, width: 393) == 0)
    }

    @Test func legacyMultiDayChoicesAdaptWithoutLosingPreference() {
        #expect(CalendarViewKind.twoDay.adaptiveValue == .twoDay)
        #expect(CalendarViewKind.week.adaptiveValue == .twoDay)
        #expect(CalendarViewKind.month.adaptiveValue == .month)
        #expect(CalendarViewKind.persistedValue("threeDay")?.adaptiveValue == .twoDay)
        #expect(CalendarViewKind.week.label == "Multi-day")
    }

    @Test func resizeSnapsToClockQuarterHoursAndHonorsMinimumDuration() throws {
        let day = date(2026, 9, 8)
        let start = date(2026, 9, 8, 9).addingTimeInterval(7 * 60)
        let entry = calendarEntry(start: start, end: start.addingTimeInterval(3600), allDay: false)
        let target = CalendarTimelineTarget(entry: entry, day: day,
            frame: CGRect(x: 59, y: CalendarTimelineGeometry.y(minute: 547), width: 160, height: 64))
        let origin = CGPoint(x: 74, y: target.frame.maxY)
        var gesture = CalendarTimelineGesture(mode: .end, target: target, origin: origin,
            location: CGPoint(x: origin.x, y: origin.y + 10))
        let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day], width: 393, calendar: calendar))
        #expect(calendar.component(.minute, from: preview.end) == 15)
        gesture.location.y -= 500
        let minimum = try #require(CalendarTimelineGeometry.preview(gesture, days: [day], width: 393, calendar: calendar))
        #expect(minimum.end.timeIntervalSince(minimum.start) >= 900)
    }

    @Test func resizingStopsAtBothMidnightsAndEdgeScrollingAccelerates() throws {
        let day = date(2026, 9, 8)
        let entry = calendarEntry(start: date(2026, 9, 8, 9), end: date(2026, 9, 8, 10), allDay: false)
        let target = CalendarTimelineTarget(entry: entry, day: day,
            frame: CGRect(x: 59, y: CalendarTimelineGeometry.y(minute: 540), width: 160, height: 64))
        for mode in [CalendarTimelineGestureMode.start, .end] {
            let gesture = CalendarTimelineGesture(mode: mode, target: target, origin: .zero,
                location: CGPoint(x: 0, y: mode == .start ? -10000 : 10000))
            let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day], width: 393, calendar: calendar))
            #expect(preview.start >= day)
            #expect(preview.end <= date(2026, 9, 9))
            #expect(preview.frame.minY >= CalendarTimelineGeometry.y(minute: 0))
            #expect(preview.frame.maxY <= CalendarTimelineGeometry.y(minute: 1440))
        }
        let initial = CalendarTimelineGeometry.edgeScrollSpeed(penetration: 60, elapsed: 0)
        #expect(CalendarTimelineGeometry.edgeScrollSpeed(penetration: 60, elapsed: 1) > initial)
        #expect(CalendarTimelineGeometry.edgeScrollSpeed(penetration: 60, elapsed: 2) <= 1000)
        #expect(CalendarTimelineGeometry.edgeScrollSpeed(penetration: 0, elapsed: 2) == 0)
    }

    @Test func overnightContinuationMovePreservesOriginalStartRelationship() throws {
        let day = date(2026, 9, 9)
        let entry = calendarEntry(start: date(2026, 9, 8, 23), end: date(2026, 9, 9, 1), allDay: false)
        let target = CalendarTimelineTarget(entry: entry, day: day,
            frame: CGRect(x: 59, y: CalendarTimelineGeometry.y(minute: 0), width: 160, height: 64))
        let origin = CGPoint(x: 100, y: 30)
        let gesture = CalendarTimelineGesture(mode: .move, target: target, origin: origin,
            location: CGPoint(x: 100, y: 94))
        let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day], width: 393, calendar: calendar))
        #expect(preview.start == date(2026, 9, 9))
        #expect(preview.end == date(2026, 9, 9, 2))
    }

    @Test func movingBetweenSnapPointsDoesNotChangeBlockHeight() throws {
        let day = date(2026, 9, 8)
        let entry = calendarEntry(start: date(2026, 9, 8, 9), end: date(2026, 9, 8, 10), allDay: false)
        let target = CalendarTimelineTarget(entry: entry, day: day,
            frame: CGRect(x: 59, y: CalendarTimelineGeometry.y(minute: 540), width: 160, height: 64))
        let origin = CGPoint(x: 100, y: target.frame.minY + 20)
        let gesture = CalendarTimelineGesture(mode: .move, target: target, origin: origin,
            location: CGPoint(x: 100, y: origin.y + 11))
        let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day], width: 393, calendar: calendar))
        #expect(preview.frame.height == target.frame.height)
        #expect(preview.frame.minY == target.frame.minY + 11)
    }

    @Test func edgePagingRevealsOneDayRegardlessOfColumnCount() {
        #expect(CalendarTimelineGeometry.pageOffset(current: 7, direction: 1, columns: 2, count: 42, editing: true) == 8)
        #expect(CalendarTimelineGeometry.pageOffset(current: 7, direction: 1, columns: 2, count: 42, editing: false) == 8)
        #expect(CalendarTimelineGeometry.pageOffset(current: 7, direction: -1, columns: 7, count: 42, editing: true) == 6)
        #expect(CalendarTimelineGeometry.pageOffset(current: 0, direction: -1, columns: 2, count: 42, editing: true) == 0)
    }

    @Test func weekStripShowsTheWholeRangeAcrossWeekAndMonthBoundaries() {
        let selected = date(2026, 5, 31)
        let next = date(2026, 6, 1)
        let strip = CalendarDateMath.weekStripDays(selected: selected, visible: [selected, next], calendar: calendar)
        #expect(strip.count == 7)
        #expect(strip.contains(selected))
        #expect(strip.contains(next))
    }

    @Test func cancelledAndStationaryGesturesCannotCommitAnEdit() throws {
        let day = date(2026, 9, 8)
        let entry = calendarEntry(start: date(2026, 9, 8, 9), end: date(2026, 9, 8, 10), allDay: false)
        let target = CalendarTimelineTarget(entry: entry, day: day,
            frame: CGRect(x: 59, y: 594, width: 160, height: 64))
        let origin = CGPoint(x: 100, y: 614)
        var gesture = CalendarTimelineGesture(mode: .move, target: target, origin: origin, location: origin)
        let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day], width: 393, calendar: calendar))
        #expect(!CalendarTimelineGeometry.shouldCommit(nil, preview: preview, calendar: calendar))
        #expect(!CalendarTimelineGeometry.shouldCommit(gesture, preview: preview, calendar: calendar))
        gesture.location.y += 64
        #expect(CalendarTimelineGeometry.shouldCommit(gesture, preview: preview, calendar: calendar))
        let projected = calendarEntry(start: entry.start, end: entry.end, allDay: false, source: .projected)
        let projectedTarget = CalendarTimelineTarget(entry: projected, day: day, frame: target.frame)
        let protected = CalendarTimelineGesture(mode: .move, target: projectedTarget, origin: origin, location: gesture.location)
        #expect(!CalendarTimelineGeometry.shouldCommit(protected, preview: preview, calendar: calendar))
    }

    @Test func crossColumnPreviewPreservesWallTimeAcrossDaylightSaving() throws {
        var local = calendar
        local.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        for monthDay in [(3, 7), (10, 31)] {
            let day = try #require(local.date(from: DateComponents(year: 2026, month: monthDay.0, day: monthDay.1)))
            let next = try #require(local.date(byAdding: .day, value: 1, to: day))
            let start = CalendarTimelineGeometry.clockDate(on: day, minute: 540, calendar: local)
            let entry = calendarEntry(start: start, end: start.addingTimeInterval(3600), allDay: false)
            let target = CalendarTimelineTarget(entry: entry, day: day,
                frame: CGRect(x: 59, y: 594, width: 160, height: 64))
            let gesture = CalendarTimelineGesture(mode: .move, target: target,
                origin: CGPoint(x: 100, y: 620), location: CGPoint(x: 300, y: 620))
            let preview = try #require(CalendarTimelineGeometry.preview(gesture, days: [day, next], width: 393, calendar: local))
            #expect(local.isDate(preview.start, inSameDayAs: next))
            #expect(local.component(.hour, from: preview.start) == 9)
            #expect(preview.end.timeIntervalSince(preview.start) == 3600)
        }
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
