import Foundation
import Testing
@testable import Lists

struct TagCountTests {
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

    @Test func tagOpenCountUsesCompletionAndPastEventRules() {
        let dailyCompletion = HabitCompletion(at: calendar.date(byAdding: .hour, value: -1, to: now)!)
        let openTask = Item(type: .task, title: "Open", listId: "inbox", tags: ["work"])
        let completedTask = Item(type: .task, title: "Done", listId: "inbox", tags: ["work"], done: true)
        let completeHabit = Item(
            type: .habit,
            title: "Hydrate",
            listId: "inbox",
            tags: ["work"],
            frequency: .daily,
            goalPerCycle: 1,
            completions: [dailyCompletion]
        )
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let pastEvent = Item(
            type: .event,
            title: "Yesterday",
            listId: "inbox",
            tags: ["work"],
            due: calendar.date(byAdding: .hour, value: 9, to: yesterday),
            end: calendar.date(byAdding: .hour, value: 10, to: yesterday)
        )
        var deleted = Item(type: .task, title: "Deleted", listId: "inbox", tags: ["work"])
        deleted.deletedAt = now

        let count = Tag.openItemCount(
            for: "WORK",
            in: [openTask, completedTask, completeHabit, pastEvent, deleted],
            now: now,
            calendar: calendar
        )

        #expect(count == 1)
    }

    @Test func activeTaggedItemsHideCompletedAndPastItemsByDefault() {
        let open = Item(type: .task, title: "Open", listId: "inbox", tags: ["work", "home"])
        let otherTag = Item(type: .task, title: "Other", listId: "inbox", tags: ["home"])
        let completed = Item(type: .task, title: "Done", listId: "inbox", tags: ["work"], done: true)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let pastEvent = Item(
            type: .event,
            title: "Past",
            listId: "inbox",
            tags: ["work"],
            due: calendar.date(byAdding: .hour, value: 9, to: yesterday),
            end: calendar.date(byAdding: .hour, value: 10, to: yesterday)
        )

        let allActive = Tag.activeItems(
            matching: [],
            in: [completed, pastEvent, otherTag, open],
            now: now,
            calendar: calendar
        )
        let selected = Tag.activeItems(
            matching: ["WORK"],
            in: [completed, pastEvent, otherTag, open],
            now: now,
            calendar: calendar
        )

        #expect(allActive.map(\.id) == [open.id, otherTag.id])
        #expect(selected.map(\.id) == [open.id])
    }

    @Test func lingeringCompletedTaggedItemStaysTemporarilyVisible() {
        let open = Item(type: .task, title: "Open", listId: "inbox", tags: ["work"])
        let completed = Item(type: .task, title: "Done", listId: "inbox", tags: ["archive"], done: true)

        let items = Tag.activeItems(
            matching: [],
            in: [completed, open],
            lingering: [completed.id],
            now: now,
            calendar: calendar
        )
        let names = Tag.activeTagNames(
            in: [completed],
            lingering: [completed.id],
            now: now,
            calendar: calendar
        )
        let archiveCount = Tag.openItemCount(
            for: "archive",
            in: [completed],
            lingering: [completed.id],
            now: now,
            calendar: calendar
        )

        #expect(items.map(\.id) == [completed.id, open.id])
        #expect(names == ["archive"])
        #expect(archiveCount == 1)
    }

    @Test func activeTagNamesHideTagsWithNoActiveItems() {
        let open = Item(type: .task, title: "Open", listId: "inbox", tags: ["work", "home"])
        let completed = Item(type: .task, title: "Done", listId: "inbox", tags: ["archive"], done: true)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let pastEvent = Item(
            type: .event,
            title: "Past",
            listId: "inbox",
            tags: ["calendar"],
            due: calendar.date(byAdding: .hour, value: 9, to: yesterday),
            end: calendar.date(byAdding: .hour, value: 10, to: yesterday)
        )

        let names = Tag.activeTagNames(
            in: [completed, pastEvent, open],
            now: now,
            calendar: calendar
        )

        #expect(Set(names) == ["work", "home"])
    }

    @Test func totalTagCountIncludesCompletedItemsForManagementCopy() {
        let open = Item(type: .task, title: "Open", listId: "inbox", tags: ["work"])
        let completed = Item(type: .task, title: "Done", listId: "inbox", tags: ["work"], done: true)
        var deleted = Item(type: .task, title: "Deleted", listId: "inbox", tags: ["work"])
        deleted.deletedAt = now

        #expect(Tag.totalItemCount(for: "work", in: [open, completed, deleted]) == 2)
    }
}
