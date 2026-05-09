import Foundation
import Testing
@testable import Lists

@Suite("SmartList predicates")
struct SmartListTests {

    /// Fixed reference moment so tests don't drift with wall-clock.
    private let now = Date(timeIntervalSince1970: 1_715_270_400) // 2024-05-09T16:00:00Z

    private func task(due: Date?, done: Bool = false, flagged: Bool = false) -> Item {
        Item(type: .task, title: "x", listId: "inbox",
             done: done, due: due, flagged: flagged)
    }

    @Test("Today: includes overdue and items due today, excludes future + done")
    func todayMatches() {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let later = cal.date(byAdding: .hour, value: 4, to: now)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!

        #expect(SmartList.today.matches(task(due: yesterday), now: now))
        #expect(SmartList.today.matches(task(due: later), now: now))
        #expect(!SmartList.today.matches(task(due: tomorrow), now: now))
        #expect(!SmartList.today.matches(task(due: yesterday, done: true), now: now))
        #expect(!SmartList.today.matches(task(due: nil), now: now))
    }

    @Test("Scheduled: future-only, undone, never habits")
    func scheduledMatches() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!

        #expect(SmartList.scheduled.matches(task(due: tomorrow), now: now))
        #expect(!SmartList.scheduled.matches(task(due: yesterday), now: now))
        #expect(!SmartList.scheduled.matches(task(due: nil), now: now))

        let habit = Item(type: .habit, title: "h", listId: "inbox", due: tomorrow)
        #expect(!SmartList.scheduled.matches(habit, now: now))
    }

    @Test("Flagged: only undone + flagged")
    func flaggedMatches() {
        #expect(SmartList.flagged.matches(task(due: nil, flagged: true), now: now))
        #expect(!SmartList.flagged.matches(task(due: nil, flagged: false), now: now))
        #expect(!SmartList.flagged.matches(task(due: nil, done: true, flagged: true), now: now))
    }

    @Test("Completed: only done items")
    func completedMatches() {
        #expect(SmartList.completed.matches(task(due: nil, done: true), now: now))
        #expect(!SmartList.completed.matches(task(due: nil, done: false), now: now))
    }

    @Test("All: undone, non-habit")
    func allMatches() {
        #expect(SmartList.all.matches(task(due: nil), now: now))
        #expect(!SmartList.all.matches(task(due: nil, done: true), now: now))
        let habit = Item(type: .habit, title: "h", listId: "inbox")
        #expect(!SmartList.all.matches(habit, now: now))
    }
}
