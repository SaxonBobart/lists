import SwiftUI

struct HabitDetailsForm: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var draft: Item
    @Binding var hasReminderTime: Bool
    @Binding var reminderTime: Date
    let lists: [ItemList]
    var onReminderEnabled: () -> Void = {}
    let onShowSectionPicker: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Form {
            titleAndTagsSection
            habitSection
            detailsSection
            deleteSection
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        // Explicit grouped backdrop so the section cards contrast against the
        // sheet in light mode.
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: normalizeVisibleReminder)
    }

    private var titleAndTagsSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.title3)
                        .lineLimit(1...6)
                        .accessibilityIdentifier("habit.title")
                    TagInputView(tags: $draft.tags)
                        .accessibilityIdentifier("habit.tags")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var habitSection: some View {
        Section("Habit") {
            Picker(selection: frequencyBinding) {
                ForEach(HabitFrequency.habitCadences, id: \.self) { f in
                    Text(f.habitDisplayName).tag(f)
                }
            } label: {
                Label("Frequency", systemImage: "repeat")
                    .labelStyle(GlyphLabelStyle())
            }
            .accessibilityIdentifier("habit.frequency")

            Toggle(isOn: $draft.flexibleGoal) {
                DetailFormRowLabel(
                    title: "Flexible streak",
                    subtitle: "One completion keeps the run going; the full goal still completes the cycle",
                    systemImage: "calendar.badge.clock"
                )
            }
            .tint(.green)
            .accessibilityIdentifier("habit.flexible.streak")

            Stepper(value: $draft.goalPerCycle, in: 1...99) {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text("Goal per cycle")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(draft.goalPerCycle)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("habit.goal")

            Toggle(isOn: reminderBinding) {
                DetailFormRowLabel(title: "Reminder", systemImage: "bell")
            }
            .tint(.green)
            .accessibilityIdentifier("habit.reminder")

            if hasReminderTime {
                if normalizedFrequency == .weekly {
                    Picker(selection: weeklyWeekdayBinding) {
                        ForEach(
                            HabitReminderSchedule.weekdayValues(calendar: reminderCalendar),
                            id: \.self
                        ) { weekday in
                            Text(HabitReminderSchedule.weekdayName(weekday, calendar: reminderCalendar))
                                .tag(weekday)
                        }
                    } label: {
                        Label("Day", systemImage: "calendar")
                            .labelStyle(GlyphLabelStyle())
                    }
                    .accessibilityIdentifier("habit.reminder.weekday")
                } else if normalizedFrequency == .monthly {
                    Picker(selection: monthlyDayBinding) {
                        ForEach(HabitReminderSchedule.supportedMonthlyDays, id: \.self) { day in
                            Text(HabitReminderSchedule.ordinal(day)).tag(day)
                        }
                    } label: {
                        Label("Day of month", systemImage: "calendar")
                            .labelStyle(GlyphLabelStyle())
                    }
                    .accessibilityIdentifier("habit.reminder.month.day")
                }

                DatePicker(
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    Label("Time", systemImage: "clock")
                        .labelStyle(GlyphLabelStyle())
                }
                .environment(\.timeZone, reminderCalendar.timeZone)
                .accessibilityIdentifier("habit.reminder.time")

                Text(reminderSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("habit.reminder.summary")
            }

            Toggle(isOn: $draft.showStreak) {
                DetailFormRowLabel(
                    title: "Show current run",
                    subtitle: currentRunExplanation,
                    systemImage: "calendar.badge.checkmark"
                )
            }
            .tint(.green)
            .accessibilityIdentifier("habit.show.run")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Toggle(isOn: $draft.flagged) {
                DetailFormRowLabel(
                    title: "Flag",
                    systemImage: draft.flagged ? "flag.fill" : "flag",
                    iconColor: draft.flagged ? ListsTokens.Semantic.warning : nil
                )
            }
            .tint(.green)
            .accessibilityIdentifier("habit.flag")

            ItemPriorityPickerRow(priority: $draft.priority)
                .accessibilityIdentifier("habit.priority")

            Button {
                onShowSectionPicker()
            } label: {
                DetailFormDisclosureRowLabel(
                    title: "Section",
                    value: resolvedSectionName,
                    systemImage: "square.dashed"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("habit.section")

            DetailFormListMenuRow(
                lists: activeLists,
                selectedListId: draft.listId,
                selectedList: selectedList
            ) { list in
                if draft.listId != list.id {
                    draft.listId = list.id
                    draft.section = nil
                }
            }
            .accessibilityIdentifier("habit.list")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Habit", systemImage: "trash")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .tint(.red)
            .accessibilityIdentifier("habit.delete")
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { hasReminderTime },
            set: { newValue in
                guard newValue != hasReminderTime else { return }
                performScheduleTransition {
                    hasReminderTime = newValue
                    if newValue {
                        let timeZoneIdentifier = ensureReminderTimeZone()
                        reminderTime = HabitReminderSchedule.normalizedReminderTime(
                            reminderTime,
                            frequency: normalizedFrequency,
                            timeZoneIdentifier: timeZoneIdentifier
                        )
                    }
                }
                if newValue { onReminderEnabled() }
            }
        )
    }

    private var frequencyBinding: Binding<HabitFrequency> {
        Binding(
            get: { normalizedFrequency },
            set: { newValue in
                performScheduleTransition {
                    draft.frequency = newValue.normalizedForHabit
                    guard hasReminderTime else { return }
                    let timeZoneIdentifier = ensureReminderTimeZone()
                    reminderTime = HabitReminderSchedule.normalizedReminderTime(
                        reminderTime,
                        frequency: newValue,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { reminderTime },
            set: { newValue in
                let timeZoneIdentifier = ensureReminderTimeZone()
                reminderTime = HabitReminderSchedule.normalizedReminderTime(
                    newValue,
                    frequency: normalizedFrequency,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
        )
    }

    private var weeklyWeekdayBinding: Binding<Int> {
        Binding(
            get: { reminderCalendar.component(.weekday, from: reminderTime) },
            set: { weekday in
                let timeZoneIdentifier = ensureReminderTimeZone()
                reminderTime = HabitReminderSchedule.replacingWeekday(
                    weekday,
                    in: reminderTime,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
        )
    }

    private var monthlyDayBinding: Binding<Int> {
        Binding(
            get: {
                min(
                    reminderCalendar.component(.day, from: reminderTime),
                    HabitReminderSchedule.supportedMonthlyDays.upperBound
                )
            },
            set: { day in
                let timeZoneIdentifier = ensureReminderTimeZone()
                reminderTime = HabitReminderSchedule.replacingMonthDay(
                    day,
                    in: reminderTime,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
        )
    }

    private var normalizedFrequency: HabitFrequency {
        (draft.frequency ?? .daily).normalizedForHabit
    }

    private var reminderCalendar: Calendar {
        HabitReminderSchedule.calendar(timeZoneIdentifier: draft.dueTimeZone)
    }

    private var reminderSummary: String {
        HabitReminderSchedule.summary(
            frequency: normalizedFrequency,
            reminderTime: reminderTime,
            timeZoneIdentifier: draft.dueTimeZone
        )
    }

    private var currentRunExplanation: String {
        if draft.flexibleGoal {
            return "Counts cycles with any progress and allows one missed cycle"
        }
        return "Counts goal-complete cycles and allows one missed cycle"
    }

    @discardableResult
    private func ensureReminderTimeZone() -> String {
        let identifier = reminderCalendar.timeZone.identifier
        if draft.dueTimeZone != identifier {
            draft.dueTimeZone = identifier
        }
        return identifier
    }

    private func normalizeVisibleReminder() {
        guard hasReminderTime else { return }
        reminderTime = HabitReminderSchedule.normalizedReminderTime(
            reminderTime,
            frequency: normalizedFrequency,
            timeZoneIdentifier: draft.dueTimeZone
        )
    }

    private func performScheduleTransition(_ updates: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth, updates)
    }

    private var activeLists: [ItemList] {
        lists.filter { $0.deletedAt == nil }.sorted { $0.position < $1.position }
    }

    private var selectedList: ItemList? {
        lists.first { $0.id == draft.listId }
    }

    private var resolvedSectionName: String? {
        guard let s = draft.section, !s.isEmpty else { return nil }
        return selectedList?.sections.first { $0.id.uuidString == s }?.name
    }

}
