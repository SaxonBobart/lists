import Foundation
import Testing
import UserNotifications
@testable import Lists

/// A habit's reminder must *repeat* (`UNCalendarNotificationTrigger` keyed to
/// the habit's cadence, built off `item.due`'s time-of-day).
///
/// The schedule is built from the habit's NORMALIZED cadence (daily / weekly /
/// monthly) — the only cadences the habit UI offers. A legacy raw frequency
/// (`hourly`, `weekdays`, `custom`, …) must not drive a reminder schedule the
/// user can no longer see or edit: an old `hourly` habit pings once a day, not
/// every hour. One trigger per habit also keeps the app far away from the iOS
/// 64-pending-notification cap.
struct HabitReminderTriggerTests {
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

    @Test func dailyReminderRepeatsAtTheDueTime() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.daily))
        #expect(triggers.count == 1)
        let t = triggers[0].trigger
        #expect(t.repeats)
        #expect(t.dateComponents.hour == expectedTime.hour)
        #expect(t.dateComponents.minute == expectedTime.minute)
        #expect(t.dateComponents.weekday == nil, "a daily reminder is not pinned to a weekday")
    }

    @Test func weeklyReminderMatchesTheDueWeekday() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekly))
        #expect(triggers.count == 1)
        let t = triggers[0].trigger
        #expect(t.repeats)
        #expect(t.dateComponents.weekday == Calendar.current.component(.weekday, from: due))
        #expect(t.dateComponents.hour == expectedTime.hour)
    }

    @Test func monthlyReminderMatchesTheDueDayOfMonth() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.monthly))
        #expect(triggers.count == 1)
        let t = triggers[0].trigger
        #expect(t.repeats)
        #expect(t.dateComponents.day == Calendar.current.component(.day, from: due))
        #expect(t.dateComponents.weekday == nil)
    }

    // MARK: - Legacy raw frequencies normalize

    @Test func hourlyNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.hourly))
        #expect(triggers.count == 1)
        let t = triggers[0].trigger
        #expect(t.dateComponents.hour == expectedTime.hour, "a legacy hourly habit must NOT ping every hour — it reads as daily")
        #expect(t.dateComponents.minute == expectedTime.minute)
        #expect(t.dateComponents.weekday == nil)
    }

    @Test func weekdaysNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekdays))
        #expect(triggers.count == 1, "no per-weekday fan-out — one trigger per habit")
        #expect(triggers[0].trigger.dateComponents.weekday == nil)
        #expect(triggers[0].suffix == "", "no wd.<n> suffixes once normalized")
    }

    @Test func weekendsNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.weekends))
        #expect(triggers.count == 1)
        #expect(triggers[0].trigger.dateComponents.weekday == nil)
    }

    @Test func customNormalizesToOneDailyTrigger() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.custom))
        #expect(triggers.count == 1)
        #expect(triggers[0].trigger.dateComponents.weekday == nil)
        #expect(triggers[0].trigger.dateComponents.hour == expectedTime.hour)
    }

    @Test func fortnightlyNormalizesToWeekly() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.fortnightly))
        #expect(triggers.count == 1)
        #expect(triggers[0].trigger.dateComponents.weekday == Calendar.current.component(.weekday, from: due))
    }

    @Test func quarterlyNormalizesToMonthly() {
        let triggers = NotificationScheduler.habitTriggers(for: habit(.everyThreeMonths))
        #expect(triggers.count == 1)
        #expect(triggers[0].trigger.dateComponents.day == Calendar.current.component(.day, from: due))
        #expect(triggers[0].trigger.dateComponents.month == nil, "monthly cadence — not pinned to one month of the year")
    }

    // MARK: - Guards

    @Test func noDueDateYieldsNoTriggers() {
        #expect(NotificationScheduler.habitTriggers(for: habit(.daily, hasDue: false)).isEmpty)
    }

    @Test func nonHabitYieldsNoTriggers() {
        var task = Item(type: .task, title: "T", listId: "inbox")
        task.due = due
        task.reminder = Reminder(enabled: true)
        #expect(NotificationScheduler.habitTriggers(for: task).isEmpty)
    }

    // MARK: - Single reminders

    @Test func singleReminderUsesCompletionSemanticsForNotes() {
        var note = Item(type: .note, title: "N", listId: "inbox", done: true)
        note.due = due
        note.reminder = Reminder(enabled: true)

        #expect(NotificationScheduler.singleReminderFireDate(for: note, now: due.addingTimeInterval(-60)) == due)
    }

    @Test func singleReminderSkipsCompletedTask() {
        var task = Item(type: .task, title: "T", listId: "inbox", done: true)
        task.due = due
        task.reminder = Reminder(enabled: true)

        #expect(NotificationScheduler.singleReminderFireDate(for: task, now: due.addingTimeInterval(-60)) == nil)
    }

    @Test func singleReminderSkipsCompletedCompletableEvent() {
        var event = Item(type: .event, title: "E", listId: "inbox", done: true, completable: true)
        event.due = due
        event.end = due.addingTimeInterval(3_600)
        event.reminder = Reminder(enabled: true)

        #expect(NotificationScheduler.singleReminderFireDate(for: event, now: due.addingTimeInterval(-60)) == nil)
    }

    @Test func singleReminderUsesEventCompletionSemantics() {
        var event = Item(type: .event, title: "E", listId: "inbox", done: true)
        event.due = due
        event.end = due.addingTimeInterval(3_600)
        event.reminder = Reminder(enabled: true)

        #expect(NotificationScheduler.singleReminderFireDate(for: event, now: due.addingTimeInterval(-60)) == due)
    }

    @Test func singleReminderIgnoresHabitsBecauseTheyUseRepeatingTriggers() {
        let item = habit(.daily)

        #expect(NotificationScheduler.singleReminderFireDate(for: item, now: due.addingTimeInterval(-60)) == nil)
    }
}
