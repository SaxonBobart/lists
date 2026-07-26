import Foundation
import Testing
@testable import Lists

struct CalendarProjectionTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func interval(
        _ startDay: Int,
        through endDayExclusive: Int
    ) -> DateInterval {
        DateInterval(
            start: date(2026, 7, startDay),
            end: date(2026, 7, endDayExclusive)
        )
    }

    private func preferences(
        recurrence: CalendarPreferences.RecurrenceVisibility = .nextOccurrence,
        completed: Bool = true,
        completedHistory: Bool = false,
        missedHistory: Bool = false,
        hiddenLists: Set<String> = []
    ) -> CalendarProjectionPreferences {
        CalendarProjectionPreferences(
            recurrenceVisibility: recurrence,
            showTasks: true,
            showEvents: true,
            showHabits: true,
            showNotes: true,
            showCompletedItems: completed,
            showCompletedHistory: completedHistory,
            showMissedHistory: missedHistory,
            hiddenListIds: hiddenLists
        )
    }

    @Test func nextOccurrenceIsTheDefaultRecurrenceProjection() {
        let item = Item(
            type: .task,
            title: "Daily",
            listId: "work",
            due: date(2026, 7, 10, 9),
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )

        let entries = CalendarProjection.entries(
            items: [item],
            in: interval(10, through: 15),
            preferences: preferences(),
            now: date(2026, 7, 10, 8),
            calendar: calendar
        )

        #expect(entries.count == 1)
        #expect(entries[0].start == date(2026, 7, 10, 9))
        #expect(entries[0].id.source == .current)
    }

    @Test func visibleRangeExpandsFutureRecurrencesWithoutMaterializingDocuments() {
        let item = Item(
            type: .event,
            title: "Daily stand-up",
            listId: "work",
            due: date(2026, 7, 10, 9),
            end: date(2026, 7, 10, 10),
            recurrence: Recurrence(rrule: "FREQ=DAILY")
        )

        let entries = CalendarProjection.entries(
            items: [item],
            in: interval(10, through: 13),
            preferences: preferences(recurrence: .visibleRange),
            now: date(2026, 7, 10, 8),
            calendar: calendar
        )

        #expect(entries.map(\.start) == [
            date(2026, 7, 10, 9),
            date(2026, 7, 11, 9),
            date(2026, 7, 12, 9)
        ])
        #expect(entries[0].isEditableOccurrence)
        #expect(entries.dropFirst().allSatisfy { $0.isProjected })
        #expect(entries.allSatisfy { $0.end.timeIntervalSince($0.start) == 3_600 })
    }

    @Test func recurrenceHistoryRequiresItsExplicitSettings() {
        let completedId = UUID()
        let missedId = UUID()
        let item = Item(
            type: .task,
            title: "Ledger",
            listId: "work",
            due: date(2026, 7, 12, 9),
            recurrence: Recurrence(rrule: "FREQ=DAILY"),
            recurrenceOccurrences: [
                RecurrenceOccurrence(
                    id: completedId,
                    scheduledAt: date(2026, 7, 10, 9),
                    status: .completed,
                    completedAt: date(2026, 7, 10, 9, 5)
                ),
                RecurrenceOccurrence(
                    id: missedId,
                    scheduledAt: date(2026, 7, 11, 9),
                    status: .missed
                ),
                RecurrenceOccurrence(
                    scheduledAt: date(2026, 7, 12, 9),
                    status: .open
                )
            ]
        )

        let hidden = CalendarProjection.entries(
            items: [item],
            in: interval(10, through: 13),
            preferences: preferences(),
            now: date(2026, 7, 12, 8),
            calendar: calendar
        )
        let shown = CalendarProjection.entries(
            items: [item],
            in: interval(10, through: 13),
            preferences: preferences(completedHistory: true, missedHistory: true),
            now: date(2026, 7, 12, 8),
            calendar: calendar
        )

        #expect(hidden.count == 1)
        #expect(shown.count == 3)
        #expect(shown.map(\.status) == [.completed, .missed, .open])
    }

    @Test func hiddenListsAreRemovedFromTheGlobalProjection() {
        let visible = Item(
            type: .task,
            title: "Visible",
            listId: "visible",
            due: date(2026, 7, 10)
        )
        let hidden = Item(
            type: .task,
            title: "Hidden",
            listId: "hidden",
            due: date(2026, 7, 10)
        )

        let entries = CalendarProjection.entries(
            items: [visible, hidden],
            in: interval(10, through: 11),
            preferences: preferences(hiddenLists: ["hidden"]),
            now: date(2026, 7, 10),
            calendar: calendar
        )

        #expect(entries.map(\.title) == ["Visible"])
    }

    @Test func habitsCanShowOnlyNextOrEveryOccurrenceInTheVisibleRange() {
        let habit = Item(
            type: .habit,
            title: "Read",
            listId: "personal",
            createdAt: date(2026, 7, 10),
            frequency: .daily
        )

        let next = CalendarProjection.entries(
            items: [habit],
            in: interval(10, through: 14),
            preferences: preferences(),
            now: date(2026, 7, 11, 12),
            calendar: calendar
        )
        let range = CalendarProjection.entries(
            items: [habit],
            in: interval(10, through: 14),
            preferences: preferences(recurrence: .visibleRange),
            now: date(2026, 7, 11, 12),
            calendar: calendar
        )

        #expect(next.map(\.start) == [date(2026, 7, 11)])
        #expect(range.map(\.start) == [
            date(2026, 7, 10),
            date(2026, 7, 11),
            date(2026, 7, 12),
            date(2026, 7, 13)
        ])
        #expect(range.allSatisfy { $0.isAllDay })
    }

    @Test func multiDayEventsOverlapEveryCoveredDay() {
        let event = Item(
            type: .event,
            title: "Conference",
            listId: "work",
            due: date(2026, 7, 10),
            dueAllDay: true,
            end: date(2026, 7, 13)
        )

        let entries = CalendarProjection.entries(
            items: [event],
            in: interval(11, through: 12),
            preferences: preferences(),
            now: date(2026, 7, 9),
            calendar: calendar
        )

        #expect(entries.count == 1)
        #expect(entries[0].start == date(2026, 7, 10))
        #expect(entries[0].end == date(2026, 7, 13))
    }
}
