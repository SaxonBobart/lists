import Foundation
import Testing
@testable import Lists

struct ScheduledSmartListSectionsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 23,
            hour: 12
        ).date!
    }

    @Test func pastCalendarEventIsDateGroupedNotOverdueWhenShown() throws {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let event = Item(
            type: .event,
            title: "Past",
            listId: "inbox",
            due: calendar.date(byAdding: .hour, value: 10, to: yesterday),
            end: calendar.date(byAdding: .hour, value: 11, to: yesterday)
        )

        let hidden = ScheduledSmartListSections.split([event], now: now, calendar: calendar)
        let shown = ScheduledSmartListSections.split(
            [event],
            showPastEvents: true,
            now: now,
            calendar: calendar
        )

        #expect(hidden.isEmpty)
        #expect(shown.map(\.kind) == [.day(yesterday)])
        #expect(!(try #require(shown.first)).isOverdue)
    }

    @Test func pastOpenTaskRequiresShowOverdue() throws {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let task = Item(
            type: .task,
            title: "Overdue",
            listId: "inbox",
            due: calendar.date(byAdding: .hour, value: 9, to: yesterday)
        )

        let hidden = ScheduledSmartListSections.split([task], now: now, calendar: calendar)
        let shown = ScheduledSmartListSections.split(
            [task],
            showOverdue: true,
            now: now,
            calendar: calendar
        )

        #expect(hidden.isEmpty)
        #expect(shown.map(\.kind) == [.overdue])
        #expect((try #require(shown.first)).isOverdue)
    }

    @Test func completedPastTaskUsesDateBucketWhenShown() throws {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let task = Item(
            type: .task,
            title: "Done",
            listId: "inbox",
            done: true,
            due: calendar.date(byAdding: .hour, value: 9, to: yesterday)
        )

        let hidden = ScheduledSmartListSections.split([task], now: now, calendar: calendar)
        let shown = ScheduledSmartListSections.split(
            [task],
            showCompleted: true,
            now: now,
            calendar: calendar
        )

        #expect(hidden.isEmpty)
        #expect(shown.map(\.kind) == [.day(yesterday)])
        #expect(!(try #require(shown.first)).isOverdue)
    }

    @Test func noteWithStaleDoneFlagStillUsesNoteCompletionRules() throws {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let note = Item(
            type: .note,
            title: "Dated note",
            listId: "inbox",
            done: true,
            due: calendar.date(byAdding: .hour, value: 9, to: tomorrow)
        )

        let shown = ScheduledSmartListSections.split([note], now: now, calendar: calendar)

        #expect(shown.map(\.kind) == [.day(tomorrow)])
        #expect(shown.first?.items.map(\.id) == [note.id])
    }

    @Test func habitsAreHiddenByDefaultAndProjectedOnceWhenEnabled() throws {
        let habit = Item(
            type: .habit,
            title: "Read",
            listId: "inbox",
            createdAt: calendar.startOfDay(for: now),
            frequency: .daily
        )

        let hidden = ScheduledSmartListSections.split([habit], now: now, calendar: calendar)
        let shown = ScheduledSmartListSections.split(
            [habit],
            showHabits: true,
            now: now,
            calendar: calendar
        )

        #expect(hidden.isEmpty)
        #expect(shown.count == 1)
        #expect(shown.first?.items.map(\.id) == [habit.id])
        #expect(shown.first?.kind == .day(calendar.startOfDay(for: now)))
    }
}
