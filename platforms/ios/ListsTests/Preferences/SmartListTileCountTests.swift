import Foundation
import Testing
@testable import Lists

struct SmartListTileCountTests {
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

    private var list: ItemList {
        ItemList(
            id: "work",
            name: "Work",
            icon: "folder",
            color: .blue,
            createdAt: now,
            modifiedAt: now,
            position: 0
        )
    }

    @Test func todayTileCountRespectsHiddenOverduePreference() {
        let today = Item(type: .task, title: "Today", listId: list.id, due: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let overdue = Item(
            type: .task,
            title: "Overdue",
            listId: list.id,
            due: calendar.date(byAdding: .hour, value: 9, to: yesterday)
        )

        #expect(SmartListTileCount.count(
            for: .today,
            lists: [list],
            items: [today, overdue],
            showOverdue: true,
            now: now,
            calendar: calendar
        ) == 2)
        #expect(SmartListTileCount.count(
            for: .today,
            lists: [list],
            items: [today, overdue],
            showOverdue: false,
            now: now,
            calendar: calendar
        ) == 1)
    }

    @Test func scheduledTileCountUsesScheduledSectionVisibility() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let future = Item(
            type: .task,
            title: "Future",
            listId: list.id,
            due: calendar.date(byAdding: .hour, value: 9, to: tomorrow)
        )
        let overdue = Item(
            type: .task,
            title: "Overdue",
            listId: list.id,
            due: calendar.date(byAdding: .hour, value: 9, to: yesterday)
        )
        let completed = Item(
            type: .task,
            title: "Done",
            listId: list.id,
            done: true,
            due: calendar.date(byAdding: .hour, value: 10, to: tomorrow)
        )
        let pastEvent = Item(
            type: .event,
            title: "Past event",
            listId: list.id,
            due: calendar.date(byAdding: .hour, value: 8, to: yesterday),
            end: calendar.date(byAdding: .hour, value: 9, to: yesterday)
        )
        let habit = Item(
            type: .habit,
            title: "Habit",
            listId: list.id,
            due: tomorrow,
            frequency: .daily
        )

        #expect(SmartListTileCount.count(
            for: .scheduled,
            lists: [list],
            items: [future, overdue, completed, pastEvent, habit],
            showCompleted: false,
            showOverdue: false,
            showPastEvents: false,
            now: now,
            calendar: calendar
        ) == 1)
        #expect(SmartListTileCount.count(
            for: .scheduled,
            lists: [list],
            items: [future, overdue, completed, pastEvent, habit],
            showCompleted: true,
            showOverdue: true,
            showPastEvents: true,
            now: now,
            calendar: calendar
        ) == 4)
    }

    @Test func allTileCountUsesRenderedHierarchyRows() {
        let parent = Item(type: .task, title: "Parent", listId: list.id)
        let child = Item(type: .task, title: "Child", listId: list.id, parentId: parent.id)
        let doneChild = Item(type: .task, title: "Done child", listId: list.id, parentId: parent.id, done: true)

        #expect(SmartListTileCount.count(
            for: .all,
            lists: [list],
            items: [parent, child, doneChild],
            showCompleted: false,
            now: now,
            calendar: calendar
        ) == 2)
        #expect(SmartListTileCount.count(
            for: .all,
            lists: [list],
            items: [parent, child, doneChild],
            showCompleted: true,
            now: now,
            calendar: calendar
        ) == 3)
    }
}
