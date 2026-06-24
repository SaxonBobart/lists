import Foundation
import Testing
@testable import Lists

/// The sidebar's "All" tile counts via `SmartList.matches`, while the opened
/// view hides completed items and habits. Sub-items obey the same rules so the
/// tile count and the screen agree.
struct SmartListAllCountTests {
    private let sectionId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private var list: ItemList {
        ItemList(
            id: "work",
            name: "Work",
            icon: "folder",
            color: .blue,
            createdAt: .now,
            modifiedAt: .now,
            position: 1,
            sections: [
                ListSection(id: sectionId, name: "Priorities", position: 1)
            ]
        )
    }

    @Test func completedSubTaskDoesNotMatchAll() {
        let child = Item(type: .task, title: "Sub", listId: "inbox",
                         parentId: UUID(), done: true)
        #expect(!SmartList.all.matches(child),
                "a completed sub-task is hidden in All, so it must not count")
    }

    @Test func habitSubItemDoesNotMatchAll() {
        let child = Item(type: .habit, title: "Sub habit", listId: "inbox",
                         parentId: UUID(), frequency: .daily)
        #expect(!SmartList.all.matches(child), "habits are excluded from All at any depth")
    }

    @Test func openSubTaskStillMatchesAll() {
        let child = Item(type: .task, title: "Sub", listId: "inbox", parentId: UUID())
        #expect(SmartList.all.matches(child),
                "open sub-tasks render nested in All and stay counted")
    }

    @Test func includeCompletedRestoresCompletedSubItems() {
        let child = Item(type: .task, title: "Sub", listId: "inbox",
                         parentId: UUID(), done: true)
        #expect(SmartList.all.matches(child, includeCompleted: true))
    }

    @Test func allSectionsBucketByListSectionAndUncategorizedFallback() throws {
        let sectioned = Item(
            type: .task,
            title: "Sectioned",
            listId: list.id,
            section: sectionId.uuidString,
            sortIndex: 2
        )
        let loose = Item(type: .task, title: "Loose", listId: list.id, sortIndex: 1)
        let staleSection = Item(
            type: .task,
            title: "Stale",
            listId: list.id,
            section: UUID().uuidString,
            sortIndex: 3
        )

        let entries = AllSmartListSections.entries(
            lists: [list],
            items: [sectioned, staleSection, loose],
            sortMode: .manual,
            sortDirection: .ascending
        )
        let entry = try #require(entries.first)

        #expect(entry.buckets.map(\.name) == [nil, "Priorities"])
        #expect(entry.buckets[0].parents.map(\.title) == ["Loose", "Stale"])
        #expect(entry.buckets[1].parents.map(\.title) == ["Sectioned"])
    }

    @Test func allSectionsHideCompletedHabitsAndRolledOffEventsByDefault() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let openTask = Item(type: .task, title: "Open", listId: list.id)
        let completed = Item(type: .task, title: "Done", listId: list.id, done: true)
        let habit = Item(type: .habit, title: "Habit", listId: list.id, frequency: .daily)
        let pastEvent = Item(
            type: .event,
            title: "Past event",
            listId: list.id,
            due: calendar.date(byAdding: .day, value: -2, to: now),
            end: calendar.date(byAdding: .day, value: -2, to: now)?.addingTimeInterval(3600)
        )

        let hidden = AllSmartListSections.entries(
            lists: [list],
            items: [openTask, completed, habit, pastEvent],
            sortMode: .manual,
            sortDirection: .ascending,
            now: now,
            calendar: calendar
        )
        let shown = AllSmartListSections.entries(
            lists: [list],
            items: [openTask, completed, habit, pastEvent],
            showCompleted: true,
            showPastEvents: true,
            sortMode: .manual,
            sortDirection: .ascending,
            now: now,
            calendar: calendar
        )

        let hiddenEntry = try #require(hidden.first)
        let shownEntry = try #require(shown.first)

        #expect(hiddenEntry.buckets.flatMap(\.parents).map(\.title) == ["Open"])
        #expect(shownEntry.buckets.flatMap(\.parents).map(\.title) == [
            "Open",
            "Done",
            "Past event"
        ])
    }
}
