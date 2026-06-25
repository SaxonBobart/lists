import Foundation
import Testing
@testable import Lists

struct QuickCaptureDraftTests {
    @Test func legacyUrgentTriggerDecodesAsAlarm() throws {
        let json = #"{"urgent":{"enabled":true}}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Triggers.self, from: json)
        let encoded = try JSONEncoder().encode(decoded)
        let encodedString = String(data: encoded, encoding: .utf8) ?? ""

        #expect(decoded.alarm?.enabled == true)
        #expect(encodedString.contains("\"alarm\""))
        #expect(!encodedString.contains("\"urgent\""))
    }

    @Test func cleanTaskDraftDoesNotAskBeforeDiscarding() {
        let draft = QuickCaptureDraft()

        #expect(!draft.isDirty(
            defaultListId: ItemList.inboxId,
            defaultSection: nil,
            defaultNewItemType: .task
        ))
    }

    @Test func whitespaceOnlyTitleDoesNotDirtyQuickCapture() {
        let draft = QuickCaptureDraft(title: "   \n ")

        #expect(!draft.isDirty(
            defaultListId: ItemList.inboxId,
            defaultSection: nil,
            defaultNewItemType: .task
        ))
    }

    @Test func scheduleFieldsDirtyTaskQuickCapture() {
        let draft = QuickCaptureDraft(hasDate: true, hasReminder: true, earlyPreset: .oneHour)

        #expect(draft.isDirty(
            defaultListId: ItemList.inboxId,
            defaultSection: nil,
            defaultNewItemType: .task
        ))
    }

    @Test func cleanHabitDefaultDoesNotAskBeforeDiscarding() {
        let draft = QuickCaptureDraft(selectedType: .habit, repeatPreset: .daily)

        #expect(!draft.isDirty(
            defaultListId: ItemList.inboxId,
            defaultSection: nil,
            defaultNewItemType: .habit
        ))
    }

    @Test func habitFieldsDirtyHabitQuickCapture() {
        let draft = QuickCaptureDraft(selectedType: .habit, goalPerCycle: 2)

        #expect(draft.isDirty(
            defaultListId: ItemList.inboxId,
            defaultSection: nil,
            defaultNewItemType: .habit
        ))
    }

    @Test func taskDraftExtractsInlineTagsAndDateOnlySchedule() {
        let due = ISO8601.date(from: "2026-06-23T09:00:00.000Z")!
        let until = ISO8601.date(from: "2026-12-23T00:00:00.000Z")!

        let item = QuickCaptureDraft(
            selectedType: .task,
            title: "Pay rates #finance",
            tags: ["work"],
            notes: "Use the payroll portal.",
            hasDate: true,
            due: due,
            hasTime: false,
            hasReminder: true,
            dueTimeZone: "Australia/Brisbane",
            repeatPreset: .daily,
            endRepeatOn: true,
            endRepeatDate: until,
            earlyPreset: .oneHour,
            priority: .high,
            section: "  admin  ",
            listId: "work"
        ).makeItem()

        #expect(item.title == "Pay rates")
        #expect(item.tags == ["work", "finance"])
        #expect(item.body == "Use the payroll portal.")
        #expect(item.due == due)
        #expect(item.dueAllDay)
        #expect(item.dueTimeZone == "Australia/Brisbane")
        #expect(item.reminder?.early?.value == 1)
        #expect(item.reminder?.early?.unit == .hour)
        #expect(item.recurrence?.rrule == "FREQ=DAILY;UNTIL=20261223T000000Z")
        #expect(item.priority == .high)
        #expect(item.section == "admin")
    }

    @Test func eventDraftAlwaysCarriesEndAndIgnoresTimeZone() {
        let start = ISO8601.date(from: "2026-06-23T12:00:00.000Z")!
        let end = ISO8601.date(from: "2026-06-23T13:00:00.000Z")!

        let item = QuickCaptureDraft(
            selectedType: .event,
            title: "Lunch",
            notes: "Corner table.",
            due: start,
            hasAlarm: true,
            dueTimeZone: "America/Los_Angeles",
            endDate: end,
            completable: true,
            allDay: true
        ).makeItem()

        #expect(item.due == start)
        #expect(item.end == end)
        #expect(item.dueAllDay)
        #expect(item.completable)
        #expect(item.dueTimeZone == nil)
        #expect(item.triggers?.alarm?.enabled == true)
        #expect(item.body == "Corner table.")
    }

    @Test func eventDraftRepairsEndBeforeStart() throws {
        let start = ISO8601.date(from: "2026-06-23T12:00:00.000Z")!
        let staleEnd = ISO8601.date(from: "2026-06-23T11:00:00.000Z")!

        let item = QuickCaptureDraft(
            selectedType: .event,
            title: "Lunch",
            due: start,
            endDate: staleEnd
        ).makeItem()

        #expect(item.due == start)
        #expect(abs(try #require(item.end).timeIntervalSince(start) - 3_600) <= 1)
    }

    @Test func undatedTaskDraftDropsDateBoundFields() {
        let due = ISO8601.date(from: "2026-06-23T09:00:00.000Z")!

        let item = QuickCaptureDraft(
            selectedType: .task,
            title: "Loose thought",
            hasDate: false,
            due: due,
            hasTime: true,
            hasReminder: true,
            hasAlarm: true,
            dueTimeZone: "Australia/Brisbane",
            repeatPreset: .daily,
            earlyPreset: .oneHour
        ).makeItem()

        #expect(item.due == nil)
        #expect(!item.dueAllDay)
        #expect(item.reminder == nil)
        #expect(item.triggers == nil)
        #expect(item.recurrence == nil)
        #expect(item.dueTimeZone == nil)
    }

    @Test func habitDraftUsesHabitFieldsAndNeverPersistsNotesBody() {
        let reminderTime = ISO8601.date(from: "2026-06-23T07:30:00.000Z")!

        let item = QuickCaptureDraft(
            selectedType: .habit,
            title: "Meditate #health",
            tags: ["wellness"],
            notes: "This must not become a habit body.",
            hasDate: true,
            hasTime: true,
            hasReminder: true,
            hasAlarm: true,
            dueTimeZone: "Australia/Brisbane",
            repeatPreset: .daily,
            flagged: true,
            priority: .medium,
            section: "health",
            listId: "personal",
            goalPerCycle: 3,
            flexibleGoal: true,
            showStreak: false,
            endDate: reminderTime.addingTimeInterval(3600),
            completable: true,
            allDay: true,
            habitFrequency: .weekly,
            hasHabitReminderTime: true,
            habitReminderTime: reminderTime
        ).makeItem()

        #expect(item.type == .habit)
        #expect(item.title == "Meditate")
        #expect(item.tags == ["wellness", "health"])
        #expect(item.body == "")
        #expect(item.due == reminderTime)
        #expect(!item.dueAllDay)
        #expect(item.dueTimeZone == nil)
        #expect(item.recurrence == nil)
        #expect(item.triggers == nil)
        #expect(item.frequency == .weekly)
        #expect(item.goalPerCycle == 3)
        #expect(item.flexibleGoal)
        #expect(!item.showStreak)
        #expect(item.end == nil)
        #expect(!item.completable)
    }
}
