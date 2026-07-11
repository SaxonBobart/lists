import Foundation
import Testing
@testable import Lists

/// Flexible "X times per week/month" habits: a `flexibleGoal` flag re-reads
/// `goalPerCycle` as "N times across the cycle" and drives calm cycle-aware
/// copy ("2 of 3 this week").
struct HabitFlexibleScheduleTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    // MARK: - flexibleGoal persistence

    @Test func flexibleGoalDefaultsFalse() {
        let item = Item(type: .habit, title: "H", listId: "inbox", frequency: .weekly)
        #expect(!item.flexibleGoal)
    }

    @Test func flexibleGoalRoundTripsWhenTrue() throws {
        var item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekly, goalPerCycle: 3)
        item.flexibleGoal = true
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(item))
        #expect(decoded.flexibleGoal)
    }

    @Test func flexibleGoalFalseIsNotWritten() throws {
        let item = Item(type: .habit, title: "Gym", listId: "inbox",
                        frequency: .weekly, goalPerCycle: 3)
        let encoded = try FrontmatterCodec.encode(item)
        #expect(!encoded.contains("flexible_goal"))
    }

    // MARK: - cycle copy

    @Test func cycleNounMatchesFrequency() {
        #expect(HabitStats.cycleNoun(for: .daily) == "today")
        #expect(HabitStats.cycleNoun(for: .weekly) == "this week")
        #expect(HabitStats.cycleNoun(for: .monthly) == "this month")
        #expect(HabitStats.cycleNoun(for: .yearly) == "this year")
    }

    // MARK: - reminder schedule presentation

    @Test func reminderCalendarUsesThePersistedSourceTimeZone() {
        let calendar = HabitReminderSchedule.calendar(
            timeZoneIdentifier: "Australia/Brisbane"
        )

        #expect(calendar.timeZone.identifier == "Australia/Brisbane")
    }

    @Test func weeklySummaryNamesTheActualSourceTimeZoneWeekday() throws {
        let calendar = HabitReminderSchedule.calendar(
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let date = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 15,
            hour: 23,
            minute: 30
        )))
        let weekday = calendar.component(.weekday, from: date)

        let summary = HabitReminderSchedule.summary(
            frequency: .weekly,
            reminderTime: date,
            timeZoneIdentifier: calendar.timeZone.identifier
        )

        #expect(summary.hasPrefix("Every "))
        #expect(summary.contains(HabitReminderSchedule.weekdayName(weekday, calendar: calendar)))
        #expect(summary.contains(" at "))
        #expect(summary.contains(":30"))
    }

    @Test func replacingWeeklyAnchorPreservesSourceWallClockTime() throws {
        let calendar = HabitReminderSchedule.calendar(
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let date = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 15,
            hour: 18,
            minute: 20
        )))
        let targetWeekday = 2

        let replaced = HabitReminderSchedule.replacingWeekday(
            targetWeekday,
            in: date,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: replaced)

        #expect(components.weekday == targetWeekday)
        #expect(components.hour == 18)
        #expect(components.minute == 20)
    }

    @Test func monthlyReminderClampsToTwentyEighthWithoutMovingWallClockTime() throws {
        let calendar = HabitReminderSchedule.calendar(
            timeZoneIdentifier: "Australia/Brisbane"
        )
        let date = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 31,
            hour: 7,
            minute: 45
        )))

        let normalized = HabitReminderSchedule.normalizedReminderTime(
            date,
            frequency: .monthly,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        let components = calendar.dateComponents([.day, .hour, .minute], from: normalized)
        let summary = HabitReminderSchedule.summary(
            frequency: .monthly,
            reminderTime: date,
            timeZoneIdentifier: calendar.timeZone.identifier
        )

        #expect(components.day == 28)
        #expect(components.hour == 7)
        #expect(components.minute == 45)
        #expect(summary.contains(HabitReminderSchedule.ordinal(28)))
        #expect(!summary.contains(HabitReminderSchedule.ordinal(31)))
    }

    // MARK: - edit-session normalization

    @Test func legacyCadenceIsACleanEditUntilThePersonActuallyChangesSomething() {
        let item = Item(
            type: .habit,
            title: "Legacy habit",
            listId: ItemList.inboxId,
            frequency: nil
        )
        var session = HabitEditSession(source: item)

        #expect(session.draft.frequency == .daily)
        #expect(!session.isDirty(live: item))

        session.draft.title = "Edited legacy habit"

        #expect(session.isDirty(live: item))
        #expect(session.itemForPersistence(live: item).frequency == .daily)
    }

    @Test func missingReminderTimeZoneIsACleanEditAndHealsWithARealEdit() {
        let reminderTime = Date(timeIntervalSince1970: 1_784_102_400)
        let item = Item(
            type: .habit,
            title: "Legacy reminder",
            listId: ItemList.inboxId,
            due: reminderTime,
            reminder: Reminder(enabled: true),
            frequency: .weekly
        )
        var session = HabitEditSession(source: item)

        #expect(session.draft.dueTimeZone == TimeZone.current.identifier)
        #expect(!session.isDirty(live: item))

        session.draft.goalPerCycle = 2
        let healed = session.itemForPersistence(live: item)

        #expect(session.isDirty(live: item))
        #expect(healed.dueTimeZone == TimeZone.current.identifier)
    }

    @Test func legacyMonthEndReminderIsACleanEditAndHealsWithARealEdit() throws {
        let calendar = HabitReminderSchedule.calendar(
            timeZoneIdentifier: "Australia/Brisbane"
        )
        let monthEnd = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 31,
            hour: 7,
            minute: 45
        )))
        var item = Item(
            type: .habit,
            title: "Pay rent",
            listId: ItemList.inboxId,
            due: monthEnd,
            reminder: Reminder(enabled: true),
            frequency: .monthly
        )
        item.dueTimeZone = calendar.timeZone.identifier
        var session = HabitEditSession(source: item)

        #expect(!session.isDirty(live: item))

        session.draft.title = "Pay rent and utilities"
        let healed = session.itemForPersistence(live: item)
        let healedDate = try #require(healed.due)

        #expect(session.isDirty(live: item))
        #expect(calendar.component(.day, from: healedDate) == 28)
    }

    @Test func togglingExistingReminderOffThenOnPreservesSourceTimeZone() {
        var item = Item(
            type: .habit,
            title: "Drink water",
            listId: ItemList.inboxId,
            due: Date(timeIntervalSince1970: 1_784_102_400),
            reminder: Reminder(enabled: true),
            frequency: .daily
        )
        item.dueTimeZone = "America/Los_Angeles"
        var session = HabitEditSession(source: item)

        session.hasReminderTime = false
        #expect(session.draft.dueTimeZone == "America/Los_Angeles")
        #expect(session.itemForPersistence(live: item).dueTimeZone == nil)

        session.hasReminderTime = true
        let reenabled = session.itemForPersistence(live: item)

        #expect(reenabled.dueTimeZone == "America/Los_Angeles")
        #expect(!session.isDirty(live: item))
    }

    // MARK: - notification recovery

    @Test func notificationRecoveryOnlyReschedulesWhenDeliveryBecomesUsable() {
        #expect(HabitNotificationStatus.shouldRescheduleAfterRecovery(
            from: .notDetermined,
            to: .enabled
        ))
        #expect(HabitNotificationStatus.shouldRescheduleAfterRecovery(
            from: .denied,
            to: .summarized
        ))
        #expect(!HabitNotificationStatus.shouldRescheduleAfterRecovery(
            from: .quiet,
            to: .enabled
        ))
        #expect(!HabitNotificationStatus.shouldRescheduleAfterRecovery(
            from: nil,
            to: .enabled
        ))
    }
}
