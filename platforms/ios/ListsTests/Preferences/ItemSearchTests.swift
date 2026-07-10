import Foundation
import Testing
@testable import Lists

struct ItemSearchTests {
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

    @Test func searchMatchesTitleBodyAndTags() {
        let title = Item(type: .task, title: "Invoice client", listId: "work")
        var body = Item(type: .note, title: "Reference", listId: "work")
        body.body = "Payroll portal notes"
        let tag = Item(type: .task, title: "Book trip", listId: "travel", tags: ["finance"])

        #expect(ItemSearch.results(in: [body, tag, title], scope: .fullText("invoice"), now: now, calendar: calendar).map(\.id) == [title.id])
        #expect(ItemSearch.results(in: [body, tag, title], scope: .fullText("payroll"), now: now, calendar: calendar).map(\.id) == [body.id])
        #expect(ItemSearch.results(in: [body, tag, title], scope: .fullText("fin"), now: now, calendar: calendar).map(\.id) == [tag.id])
    }

    @Test func searchHidesCompletedDeletedAndRolledOffPastEvents() {
        let open = Item(type: .task, title: "Finance open", listId: "work")
        let completed = Item(type: .task, title: "Finance done", listId: "work", done: true)
        var deleted = Item(type: .task, title: "Finance deleted", listId: "work")
        deleted.deletedAt = now

        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let pastEvent = Item(
            type: .event,
            title: "Finance past event",
            listId: "work",
            due: calendar.date(byAdding: .hour, value: 9, to: yesterday),
            end: calendar.date(byAdding: .hour, value: 10, to: yesterday)
        )

        let results = ItemSearch.results(
            in: [completed, deleted, pastEvent, open],
            scope: .fullText("finance"),
            now: now,
            calendar: calendar
        )

        #expect(results.map(\.id) == [open.id])
    }

    @Test func searchKeepsLingeringCompletedMatchTemporarilyVisible() {
        let open = Item(type: .task, title: "Finance open", listId: "work")
        let completed = Item(type: .task, title: "Finance done", listId: "work", done: true)

        let results = ItemSearch.results(
            in: [completed, open],
            scope: .fullText("finance"),
            lingering: [completed.id],
            now: now,
            calendar: calendar
        )

        #expect(results.map(\.id) == [completed.id, open.id])
    }

    @Test func searchRespectsItemTypePolicy() {
        let habit = Item(
            type: .habit,
            title: "Finance habit",
            listId: "work",
            frequency: .daily
        )
        let task = Item(type: .task, title: "Finance task", listId: "work")

        let hidden = ItemSearch.results(
            in: [habit, task],
            scope: .fullText("finance"),
            itemTypePolicy: ItemTypePolicy(habitsEnabled: false),
            now: now,
            calendar: calendar
        )

        #expect(hidden.map(\.id) == [task.id])
        #expect(
            ItemSearch.results(
                in: [habit, task],
                scope: .itemType(.habit),
                itemTypePolicy: ItemTypePolicy(habitsEnabled: false),
                now: now,
                calendar: calendar
            ).isEmpty
        )
    }

    @Test func itemTypeScopesMatchEveryItemType() {
        let task = Item(type: .task, title: "Alpha", listId: "work")
        let habit = Item(type: .habit, title: "Bravo", listId: "work", frequency: .daily)
        let note = Item(type: .note, title: "Charlie", listId: "work")
        let event = Item(type: .event, title: "Delta", listId: "work")
        let items = [event, note, habit, task]

        #expect(ItemSearch.results(in: items, scope: .itemType(.task), now: now, calendar: calendar).map(\.id) == [task.id])
        #expect(ItemSearch.results(in: items, scope: .itemType(.habit), now: now, calendar: calendar).map(\.id) == [habit.id])
        #expect(ItemSearch.results(in: items, scope: .itemType(.note), now: now, calendar: calendar).map(\.id) == [note.id])
        #expect(ItemSearch.results(in: items, scope: .itemType(.event), now: now, calendar: calendar).map(\.id) == [event.id])
    }

    @Test func metadataScopesMatchTagsAndFlags() {
        let tagged = Item(type: .note, title: "Alpha", listId: "work", tags: ["reference"])
        let flagged = Item(type: .event, title: "Bravo", listId: "work", flagged: true)
        let neither = Item(type: .task, title: "Charlie", listId: "work")
        let items = [neither, flagged, tagged]

        #expect(ItemSearch.results(in: items, scope: .hasTags, now: now, calendar: calendar).map(\.id) == [tagged.id])
        #expect(ItemSearch.results(in: items, scope: .flagged, now: now, calendar: calendar).map(\.id) == [flagged.id])
    }

    @Test func typedScopesHideCompletedAndDeletedMatches() {
        let active = Item(
            type: .task,
            title: "Active",
            listId: "work",
            tags: ["focus"],
            flagged: true
        )
        let completed = Item(
            type: .task,
            title: "Completed",
            listId: "work",
            tags: ["focus"],
            done: true,
            flagged: true
        )
        var deleted = Item(
            type: .task,
            title: "Deleted",
            listId: "work",
            tags: ["focus"],
            flagged: true
        )
        deleted.deletedAt = now
        let items = [completed, deleted, active]

        #expect(ItemSearch.results(in: items, scope: .itemType(.task), now: now, calendar: calendar).map(\.id) == [active.id])
        #expect(ItemSearch.results(in: items, scope: .hasTags, now: now, calendar: calendar).map(\.id) == [active.id])
        #expect(ItemSearch.results(in: items, scope: .flagged, now: now, calendar: calendar).map(\.id) == [active.id])
    }

    @Test func searchResultsGroupByListNameAndDueDate() throws {
        let work = ItemList(
            id: "work",
            name: "Work",
            icon: "folder",
            color: .blue,
            createdAt: now,
            modifiedAt: now,
            position: 1
        )
        let home = ItemList(
            id: "home",
            name: "Home",
            icon: "house",
            color: .green,
            createdAt: now,
            modifiedAt: now,
            position: 2
        )
        let later = Item(type: .task, title: "Later", listId: "work", due: calendar.date(byAdding: .hour, value: 2, to: now))
        let sooner = Item(type: .task, title: "Sooner", listId: "work", due: calendar.date(byAdding: .hour, value: 1, to: now))
        let homeItem = Item(type: .task, title: "Home", listId: "home", due: now)

        let groups = ItemSearch.groupedByList([later, homeItem, sooner], lists: [work, home])
        let homeGroup = try #require(groups.first)
        let workGroup = try #require(groups.dropFirst().first)

        #expect(homeGroup.listName == "Home")
        #expect(homeGroup.items.map(\.id) == [homeItem.id])
        #expect(workGroup.listName == "Work")
        #expect(workGroup.items.map(\.id) == [sooner.id, later.id])
    }
}
