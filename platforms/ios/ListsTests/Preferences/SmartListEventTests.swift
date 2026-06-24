import Foundation
import Testing
@testable import Lists

/// Event semantics in the smart lists: a passed non-completable event has no
/// failure state. It becomes the past; it does not nag like an overdue task.
struct SmartListEventTests {

    private let cal = Calendar.current

    private func event(startingDaysAgo days: Int, end: Date? = nil,
                       completable: Bool = false) -> Item {
        Item(type: .event, title: "E", listId: "inbox",
             due: cal.date(byAdding: .day, value: -days, to: .now),
             end: end, completable: completable)
    }

    @Test func todaysEventAppearsInToday() {
        #expect(SmartList.today.matches(event(startingDaysAgo: 0)))
    }

    @Test func yesterdaysEventIsNotOverdueInToday() {
        #expect(!SmartList.today.matches(event(startingDaysAgo: 1)),
                "a passed event does nothing — it must not linger in Today like an overdue task")
    }

    @Test func ongoingMultiDayEventStaysInToday() {
        let ongoing = event(startingDaysAgo: 1, end: cal.date(byAdding: .day, value: 1, to: .now))
        #expect(SmartList.today.matches(ongoing),
                "a span that overlaps today is happening today")
    }

    @Test func eventEndingAtStartOfTodayIsPast() {
        let startOfToday = cal.startOfDay(for: .now)
        let endedAtMidnight = event(startingDaysAgo: 1, end: startOfToday)

        #expect(!SmartList.today.matches(endedAtMidnight))
        #expect(TodaySmartListSections.split([endedAtMidnight]).today.isEmpty)
    }

    @Test func ongoingMultiDayEventRendersInTodaySection() {
        let ongoing = event(startingDaysAgo: 1, end: cal.date(byAdding: .day, value: 1, to: .now))
        let sections = TodaySmartListSections.split([ongoing])

        #expect(sections.overdue.isEmpty)
        #expect(sections.today.map(\.id) == [ongoing.id])
    }

    @Test func completableEventGoesOverdueLikeATask() {
        #expect(SmartList.today.matches(event(startingDaysAgo: 1, completable: true)),
                "an unticked completable event keeps nagging — that's what the checkbox means")
    }

    @Test func completableEventRendersInOverdueSection() {
        let event = event(startingDaysAgo: 1, completable: true)
        let sections = TodaySmartListSections.split([event])

        #expect(sections.overdue.map(\.id) == [event.id])
        #expect(sections.today.isEmpty)
    }

    @Test func completedPastTaskIsNotTodayWhenShowingCompleted() {
        let completed = Item(type: .task, title: "Done", listId: "inbox",
                             done: true, due: cal.date(byAdding: .day, value: -1, to: .now))

        #expect(!SmartList.today.matches(completed, includeCompleted: true))
        #expect(TodaySmartListSections.split([completed]).overdue.isEmpty)
    }

    @Test func completedTaskDueTodayCanShowInTodayWhenCompletedAreShown() {
        let completed = Item(type: .task, title: "Done", listId: "inbox",
                             done: true, due: .now)
        let sections = TodaySmartListSections.split([completed])

        #expect(SmartList.today.matches(completed, includeCompleted: true))
        #expect(sections.today.map(\.id) == [completed.id])
        #expect(sections.overdue.isEmpty)
    }

    @Test func lingeringCompletedPastTaskCanRemainInOverdueBriefly() {
        let completed = Item(type: .task, title: "Done", listId: "inbox",
                             done: true, due: cal.date(byAdding: .day, value: -1, to: .now))
        let sections = TodaySmartListSections.split([completed], lingering: [completed.id])

        #expect(sections.overdue.map(\.id) == [completed.id])
        #expect(sections.today.isEmpty)
    }

    @Test func futureEventIsScheduled() {
        let future = Item(type: .event, title: "E", listId: "inbox",
                          due: cal.date(byAdding: .day, value: 3, to: .now))
        #expect(SmartList.scheduled.matches(future))
    }

    @Test func passedEventIsNeverInCompleted() {
        #expect(!SmartList.completed.matches(event(startingDaysAgo: 2)),
                "past is not the same thing as completed")
    }

    @MainActor
    @Test func storeQueryHidesRolledOffPastEventsByDefault() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartListEvents-\(UUID().uuidString)")
        let store = ItemStore(store: FileStore(root: root))
        try await store.bootstrap()
        let past = event(startingDaysAgo: 2)
        try await store.add(past)

        #expect(!store.items(for: .all).contains { $0.id == past.id })
        #expect(store.items(for: .all, showPastEvents: true).contains { $0.id == past.id })
    }
}
