import XCTest
@testable import Lists

/// PREF-1: the persisted auto-list order is de-duplicated on read, so a corrupt
/// UserDefaults payload with a repeated id can't make a SmartList appear twice
/// (which yields undefined rows / broken drag-reorder in the Edit-Lists screen).
final class AutoListPreferencesTests: XCTestCase {

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "AutoListPrefsTest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return (d, name)
    }

    func testDuplicateOrderEntriesAreDeduplicated() {
        let (d, name) = freshDefaults()
        defer { d.removePersistentDomain(forName: name) }
        d.set(["today", "scheduled", "today", "flagged", "scheduled"],
              forKey: "lists.autolists.order.v1")

        let prefs = AutoListPreferences(defaults: d)

        XCTAssertEqual(prefs.order.count, Set(prefs.order).count, "no SmartList appears twice")
        XCTAssertEqual(Set(prefs.order), Set(SmartList.allCases), "every smart list present exactly once")
        XCTAssertEqual(Array(prefs.order.prefix(3)), [.today, .scheduled, .flagged],
                       "first-seen order of the stored prefix is preserved")
    }

    func testUnknownOrderEntriesAreDroppedNotDuplicated() {
        let (d, name) = freshDefaults()
        defer { d.removePersistentDomain(forName: name) }
        d.set(["bogus", "today", "garbage"], forKey: "lists.autolists.order.v1")

        let prefs = AutoListPreferences(defaults: d)

        XCTAssertEqual(prefs.order.first, .today, "known ids survive; unknown ids are dropped")
        XCTAssertEqual(Set(prefs.order), Set(SmartList.allCases))
        XCTAssertEqual(prefs.order.count, SmartList.allCases.count)
    }

    func testEmptyOrderFallsBackToDefault() {
        let (d, name) = freshDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let prefs = AutoListPreferences(defaults: d)
        XCTAssertEqual(prefs.order, AutoListPreferences.defaultOrder)
    }
}

/// SMART-ALL-1: the sidebar's "All" tile counts via `SmartList.matches`, but
/// the opened view hides completed items and habits — sub-items must obey the
/// same rules, or the tile count and the screen disagree.
final class SmartListAllCountTests: XCTestCase {

    func testCompletedSubTaskDoesNotMatchAll() {
        let child = Item(type: .task, title: "Sub", listId: "inbox",
                         parentId: UUID(), done: true)
        XCTAssertFalse(SmartList.all.matches(child),
                       "a completed sub-task is hidden in All, so it must not count")
    }

    func testHabitSubItemDoesNotMatchAll() {
        let child = Item(type: .habit, title: "Sub habit", listId: "inbox",
                         parentId: UUID(), frequency: .daily)
        XCTAssertFalse(SmartList.all.matches(child), "habits are excluded from All at any depth")
    }

    func testOpenSubTaskStillMatchesAll() {
        let child = Item(type: .task, title: "Sub", listId: "inbox", parentId: UUID())
        XCTAssertTrue(SmartList.all.matches(child),
                      "open sub-tasks render nested in All and stay counted")
    }

    func testIncludeCompletedRestoresCompletedSubItems() {
        let child = Item(type: .task, title: "Sub", listId: "inbox",
                         parentId: UUID(), done: true)
        XCTAssertTrue(SmartList.all.matches(child, includeCompleted: true))
    }
}

/// Event semantics in the smart lists: a passed non-completable event has no
/// failure state — it becomes the past, it does not nag like an overdue task.
final class SmartListEventTests: XCTestCase {

    private let cal = Calendar.current

    private func event(startingDaysAgo days: Int, end: Date? = nil,
                       completable: Bool = false) -> Item {
        Item(type: .event, title: "E", listId: "inbox",
             due: cal.date(byAdding: .day, value: -days, to: .now),
             end: end, completable: completable)
    }

    func testTodaysEventAppearsInToday() {
        XCTAssertTrue(SmartList.today.matches(event(startingDaysAgo: 0)))
    }

    func testYesterdaysEventIsNotOverdueInToday() {
        XCTAssertFalse(SmartList.today.matches(event(startingDaysAgo: 1)),
                       "a passed event does nothing — it must not linger in Today like an overdue task")
    }

    func testOngoingMultiDayEventStaysInToday() {
        let ongoing = event(startingDaysAgo: 1, end: cal.date(byAdding: .day, value: 1, to: .now))
        XCTAssertTrue(SmartList.today.matches(ongoing),
                      "a span that overlaps today is happening today")
    }

    func testCompletableEventGoesOverdueLikeATask() {
        XCTAssertTrue(SmartList.today.matches(event(startingDaysAgo: 1, completable: true)),
                      "an unticked completable event keeps nagging — that's what the checkbox means")
    }

    func testFutureEventIsScheduled() {
        let future = Item(type: .event, title: "E", listId: "inbox",
                          due: cal.date(byAdding: .day, value: 3, to: .now))
        XCTAssertTrue(SmartList.scheduled.matches(future))
    }

    func testPassedEventIsNeverInCompleted() {
        XCTAssertFalse(SmartList.completed.matches(event(startingDaysAgo: 2)),
                       "past is not the same thing as completed")
    }
}
