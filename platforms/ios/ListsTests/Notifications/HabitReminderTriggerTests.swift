import XCTest
import UserNotifications
@testable import Lists

/// REM-1: a habit's reminder must *repeat*. The old scheduler built a single
/// `repeats: false` trigger off `item.due`, so a "daily" reminder fired once and
/// never again. `NotificationScheduler.habitTriggers(for:)` now builds repeating
/// `UNCalendarNotificationTrigger`s keyed to the habit's frequency.
final class HabitReminderTriggerTests: XCTestCase {

    private let due = ISO8601.date(from: "2026-05-20T09:30:00.000Z")!  // a Wednesday

    private func habit(_ freq: HabitFrequency, enabled: Bool = true, hasDue: Bool = true) -> Item {
        var item = Item(type: .habit, title: "H", listId: "inbox", frequency: freq, goalPerCycle: 1)
        if hasDue { item.due = due }
        item.reminder = Reminder(enabled: enabled)
        return item
    }

    /// Hour/minute the scheduler should extract from `due`, in the same calendar
    /// it uses — so the assertion is timezone-independent.
    private var expectedTime: DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: due)
    }

    func testDailyReminderRepeatsAtTheDueTime() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.daily))
        XCTAssertEqual(triggers.count, 1)
        let t = triggers[0].trigger
        XCTAssertTrue(t.repeats)
        XCTAssertEqual(t.dateComponents.hour, expectedTime.hour)
        XCTAssertEqual(t.dateComponents.minute, expectedTime.minute)
        XCTAssertNil(t.dateComponents.weekday, "a daily reminder is not pinned to a weekday")
    }

    func testWeekdaysProducesFiveWeekdayTriggers() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekdays))
        XCTAssertEqual(triggers.count, 5)
        XCTAssertEqual(Set(triggers.compactMap { $0.trigger.dateComponents.weekday }), [2, 3, 4, 5, 6])
        XCTAssertTrue(triggers.allSatisfy { $0.trigger.repeats })
        XCTAssertEqual(Set(triggers.map(\.suffix)), ["wd.2", "wd.3", "wd.4", "wd.5", "wd.6"],
                       "suffixed ids let cancel() clear every weekday request")
    }

    func testWeekendsProducesTwoWeekendTriggers() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekends))
        XCTAssertEqual(triggers.count, 2)
        XCTAssertEqual(Set(triggers.compactMap { $0.trigger.dateComponents.weekday }), [1, 7])
    }

    func testWeeklyReminderMatchesTheDueWeekday() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekly))
        XCTAssertEqual(triggers.count, 1)
        let t = triggers[0].trigger
        XCTAssertTrue(t.repeats)
        XCTAssertEqual(t.dateComponents.weekday, Calendar.current.component(.weekday, from: due))
        XCTAssertEqual(t.dateComponents.hour, expectedTime.hour)
    }

    func testMonthlyReminderMatchesTheDueDayOfMonth() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.monthly))
        XCTAssertEqual(triggers.count, 1)
        let t = triggers[0].trigger
        XCTAssertTrue(t.repeats)
        XCTAssertEqual(t.dateComponents.day, Calendar.current.component(.day, from: due))
        XCTAssertNil(t.dateComponents.weekday)
    }

    func testHourlyReminderRepeatsOnMinute() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.hourly))
        XCTAssertEqual(triggers.count, 1)
        let t = triggers[0].trigger
        XCTAssertTrue(t.repeats)
        XCTAssertEqual(t.dateComponents.minute, expectedTime.minute)
        XCTAssertNil(t.dateComponents.hour, "an hourly reminder must not pin an hour")
    }

    func testNoDueDateYieldsNoTriggers() {
        XCTAssertTrue(NotificationScheduler.habitTriggers(for: habit(.daily, hasDue: false)).isEmpty)
    }

    func testNonHabitYieldsNoTriggers() {
        var task = Item(type: .task, title: "T", listId: "inbox")
        task.due = due
        task.reminder = Reminder(enabled: true)
        XCTAssertTrue(NotificationScheduler.habitTriggers(for: task).isEmpty)
    }
}
