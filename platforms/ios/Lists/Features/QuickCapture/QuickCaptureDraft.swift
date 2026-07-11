import Foundation

struct QuickCaptureDraft {
    var selectedType: Item.ItemType = .task
    var title: String = ""
    var tags: [String] = []
    var notes: String = ""

    var hasDate: Bool = false
    var due: Date = ReminderPreferences.defaultTime()
    var hasTime: Bool = false
    var hasReminder: Bool = false
    var hasAlarm: Bool = false
    var dueTimeZone: String?

    var repeatPreset: RepeatPreset = .never
    var customRRule: String?
    var endRepeatOn: Bool = false
    var endRepeatDate: Date = ScheduleFormatting.defaultEndRepeat()
    var earlyPreset: EarlyReminderPreset = .none
    var customEarly: EarlyReminder?

    var flagged: Bool = false
    var priority: Item.Priority = .none
    var section: String?
    var listId: String = ItemList.inboxId
    var goalPerCycle: Int = 1
    var flexibleGoal: Bool = false
    var showStreak: Bool = true

    var endDate: Date = ReminderPreferences.defaultTime().addingTimeInterval(3600)
    var completable: Bool = false
    var allDay: Bool = false

    var habitFrequency: HabitFrequency = .daily
    var hasHabitReminderTime: Bool = false
    var habitReminderTime: Date = ReminderPreferences.defaultTime()
    /// The zone in which the reminder's weekday/day/time was chosen. Keep this
    /// separate from `dueTimeZone`: that field belongs to task due dates and
    /// can remain populated while the type picker moves between item kinds.
    var habitReminderTimeZone: String = TimeZone.current.identifier

    /// True when the user has changed anything that should trigger the discard
    /// confirmation in `QuickCaptureSheet`.
    func isDirty(
        defaultListId: String,
        defaultSection: String?,
        defaultNewItemType: Item.ItemType
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSection = normalizedSectionValue(section)
        let normalizedDefaultSection = normalizedSectionValue(defaultSection)
        let commonDirty = !trimmedTitle.isEmpty
            || !tags.isEmpty
            || !notes.isEmpty
            || selectedType != defaultNewItemType
            || flagged
            || priority != .none
            || normalizedSection != normalizedDefaultSection
            || listId != defaultListId

        if selectedType == .habit {
            return commonDirty
                || habitFrequency != .daily
                || hasHabitReminderTime
                || goalPerCycle != 1
                || flexibleGoal
                || !showStreak
        }

        let initialRepeat: RepeatPreset = defaultNewItemType == .habit ? .daily : .never
        return commonDirty
            || hasDate
            || hasTime
            || hasReminder
            || hasAlarm
            || repeatPreset != initialRepeat
            || endRepeatOn
            || earlyPreset != .none
            || customRRule != nil
            || customEarly != nil
            || completable
    }

    func makeItem() -> Item {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolvedSchedule()

        var item = Item(
            type: selectedType,
            title: trimmedTitle,
            listId: listId,
            section: section?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            tags: tags,
            due: resolved.due,
            dueAllDay: resolved.dueAllDay,
            dueTimeZone: resolved.timeZone,
            priority: priority,
            flagged: flagged,
            reminder: resolved.reminder,
            recurrence: resolved.recurrence,
            triggers: resolved.triggers,
            frequency: resolved.frequency,
            goalPerCycle: selectedType == .habit ? goalPerCycle : 1,
            showStreak: selectedType == .habit ? showStreak : true,
            flexibleGoal: selectedType == .habit ? flexibleGoal : false
        )

        item.body = selectedType == .habit ? "" : notes
        if selectedType == .event {
            item.end = endDate
            item.completable = completable
            EventDefaults.normalize(&item)
        }
        return item
    }

    private func normalizedSectionValue(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func resolvedSchedule()
        -> (due: Date?, dueAllDay: Bool, reminder: Reminder?, triggers: Triggers?,
            recurrence: Recurrence?, frequency: HabitFrequency?, timeZone: String?) {
        switch selectedType {
        case .task, .note:
            let early = resolvedEarlyReminder()
            let scheduledDue = hasDate ? due : nil
            return (
                due: scheduledDue,
                dueAllDay: hasDate && !hasTime,
                reminder: scheduledDue != nil && hasReminder ? Reminder(enabled: true, early: early) : nil,
                triggers: scheduledDue != nil && hasAlarm ? Triggers(alarm: TriggerToggle(enabled: true)) : nil,
                recurrence: scheduledDue != nil ? composedRRule().map { Recurrence(rrule: $0) } : nil,
                frequency: nil,
                timeZone: scheduledDue != nil ? dueTimeZone : nil
            )

        case .event:
            let early = resolvedEarlyReminder()
            return (
                due: due,
                dueAllDay: allDay,
                reminder: hasReminder ? Reminder(enabled: true, early: early) : nil,
                triggers: hasAlarm ? Triggers(alarm: TriggerToggle(enabled: true)) : nil,
                recurrence: composedRRule().map { Recurrence(rrule: $0) },
                frequency: nil,
                timeZone: nil
            )

        case .habit:
            let frequency = habitFrequency.normalizedForHabit
            let reminderTimeZone = HabitReminderSchedule
                .calendar(timeZoneIdentifier: habitReminderTimeZone)
                .timeZone
                .identifier
            let normalizedReminderTime = HabitReminderSchedule.normalizedReminderTime(
                habitReminderTime,
                frequency: frequency,
                timeZoneIdentifier: reminderTimeZone
            )
            return (
                due: hasHabitReminderTime ? normalizedReminderTime : nil,
                dueAllDay: false,
                reminder: hasHabitReminderTime ? Reminder(enabled: true, early: nil) : nil,
                triggers: nil,
                recurrence: nil,
                frequency: frequency,
                // A repeating habit reminder is a floating wall-clock schedule.
                // Keep the source zone beside the legacy absolute `due` instant
                // so weekday/day/time extraction remains stable after travel.
                timeZone: hasHabitReminderTime ? reminderTimeZone : nil
            )
        }
    }

    private func resolvedEarlyReminder() -> EarlyReminder? {
        earlyPreset == .custom ? customEarly : earlyPreset.value
    }

    private func composedRRule() -> String? {
        let base = repeatPreset == .custom ? customRRule : repeatPreset.rrule
        guard let base else { return nil }
        return endRepeatOn ? "\(base);UNTIL=\(ScheduleFormatting.formatUntil(endRepeatDate))" : base
    }

}
