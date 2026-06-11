import XCTest
import UserNotifications
@testable import Lists

/// REM-1: a habit's reminder must *repeat* (`UNCalendarNotificationTrigger`
/// keyed to the habit's cadence, built off `item.due`'s time-of-day).
///
/// SCHED-2/3: the schedule is built from the habit's NORMALIZED cadence
/// (daily / weekly / monthly) — the only cadences the habit UI offers. A
/// legacy raw frequency (`hourly`, `weekdays`, `custom`, …) must not drive a
/// reminder schedule the user can no longer see or edit: an old `hourly`
/// habit pings once a day, not every hour. One trigger per habit, which also
/// keeps the app far away from the iOS 64-pending-notification cap (SCHED-1).
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

    // MARK: - Legacy raw frequencies normalize (SCHED-2/3)

    func testHourlyNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.hourly))
        XCTAssertEqual(triggers.count, 1)
        let t = triggers[0].trigger
        XCTAssertEqual(t.dateComponents.hour, expectedTime.hour,
                       "a legacy hourly habit must NOT ping every hour — it reads as daily")
        XCTAssertEqual(t.dateComponents.minute, expectedTime.minute)
        XCTAssertNil(t.dateComponents.weekday)
    }

    func testWeekdaysNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekdays))
        XCTAssertEqual(triggers.count, 1, "no per-weekday fan-out — one trigger per habit")
        XCTAssertNil(triggers[0].trigger.dateComponents.weekday)
        XCTAssertEqual(triggers[0].suffix, "", "no wd.<n> suffixes once normalized")
    }

    func testWeekendsNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekends))
        XCTAssertEqual(triggers.count, 1)
        XCTAssertNil(triggers[0].trigger.dateComponents.weekday)
    }

    func testCustomNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.custom))
        XCTAssertEqual(triggers.count, 1)
        XCTAssertNil(triggers[0].trigger.dateComponents.weekday)
        XCTAssertEqual(triggers[0].trigger.dateComponents.hour, expectedTime.hour)
    }

    func testFortnightlyNormalizesToWeekly() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.fortnightly))
        XCTAssertEqual(triggers.count, 1)
        XCTAssertEqual(triggers[0].trigger.dateComponents.weekday,
                       Calendar.current.component(.weekday, from: due))
    }

    func testQuarterlyNormalizesToMonthly() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.everyThreeMonths))
        XCTAssertEqual(triggers.count, 1)
        XCTAssertEqual(triggers[0].trigger.dateComponents.day,
                       Calendar.current.component(.day, from: due))
        XCTAssertNil(triggers[0].trigger.dateComponents.month,
                      "monthly cadence — not pinned to one month of the year")
    }

    // MARK: - Guards

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
