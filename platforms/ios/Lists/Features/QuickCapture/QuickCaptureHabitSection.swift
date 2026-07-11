import SwiftUI

/// Habit creation keeps the persisted legacy due shape while exposing every
/// repeating component that shape carries: weekday for weekly reminders and a
/// reliable 1...28 day anchor for monthly reminders.
struct QuickCaptureHabitSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var frequency: HabitFrequency
    @Binding var goalPerCycle: Int
    @Binding var flexibleGoal: Bool
    @Binding var hasReminderTime: Bool
    @Binding var reminderTime: Date
    @Binding var showStreak: Bool
    let timeZoneIdentifier: String

    var body: some View {
        Section("Habit") {
            Picker(selection: frequencyBinding) {
                ForEach(HabitFrequency.habitCadences, id: \.self) { frequency in
                    Text(frequency.habitDisplayName)
                        .tag(frequency)
                }
            } label: {
                Label("Frequency", systemImage: "repeat")
                    .labelStyle(GlyphLabelStyle())
            }
            .accessibilityIdentifier("quickcapture.habit.frequency")

            Toggle(isOn: $flexibleGoal) {
                DetailFormRowLabel(
                    title: "Flexible streak",
                    subtitle: "Any progress keeps the streak; the full goal still completes the cycle",
                    systemImage: "calendar.badge.clock"
                )
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.habit.flexible.streak")

            Stepper(value: $goalPerCycle, in: 1...99) {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text("Goal per cycle")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(goalPerCycle)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("quickcapture.habit.goal")

            Toggle(isOn: reminderBinding) {
                DetailFormRowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.habit.reminder")

            if hasReminderTime {
                if frequency.normalizedForHabit == .weekly {
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
                    .accessibilityIdentifier("quickcapture.habit.reminder.weekday")
                } else if frequency.normalizedForHabit == .monthly {
                    Picker(selection: monthlyDayBinding) {
                        ForEach(HabitReminderSchedule.supportedMonthlyDays, id: \.self) { day in
                            Text(HabitReminderSchedule.ordinal(day)).tag(day)
                        }
                    } label: {
                        Label("Day of month", systemImage: "calendar")
                            .labelStyle(GlyphLabelStyle())
                    }
                    .accessibilityIdentifier("quickcapture.habit.reminder.month.day")
                }

                DatePicker(
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    Label("Time", systemImage: "clock")
                        .labelStyle(GlyphLabelStyle())
                }
                .environment(\.timeZone, reminderCalendar.timeZone)
                .accessibilityIdentifier("quickcapture.habit.reminder.time")

                Text(reminderSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("quickcapture.habit.reminder.summary")
            }

            Toggle(isOn: $showStreak) {
                DetailFormRowLabel(
                    title: "Show current run",
                    subtitle: "One missed cycle is forgiven; two in a row end the run",
                    systemImage: "calendar.badge.checkmark"
                )
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.habit.show.run")
        }
        .onAppear(perform: normalizeVisibleReminder)
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { hasReminderTime },
            set: { newValue in
                guard newValue != hasReminderTime else { return }
                performScheduleTransition {
                    hasReminderTime = newValue
                    if newValue {
                        reminderTime = HabitReminderSchedule.normalizedReminderTime(
                            reminderTime,
                            frequency: frequency,
                            timeZoneIdentifier: sourceTimeZoneIdentifier
                        )
                    }
                }
            }
        )
    }

    private var frequencyBinding: Binding<HabitFrequency> {
        Binding(
            get: { frequency.normalizedForHabit },
            set: { newValue in
                performScheduleTransition {
                    frequency = newValue.normalizedForHabit
                    if hasReminderTime {
                        reminderTime = HabitReminderSchedule.normalizedReminderTime(
                            reminderTime,
                            frequency: newValue,
                            timeZoneIdentifier: sourceTimeZoneIdentifier
                        )
                    }
                }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { reminderTime },
            set: { newValue in
                reminderTime = HabitReminderSchedule.normalizedReminderTime(
                    newValue,
                    frequency: frequency,
                    timeZoneIdentifier: sourceTimeZoneIdentifier
                )
            }
        )
    }

    private var weeklyWeekdayBinding: Binding<Int> {
        Binding(
            get: { reminderCalendar.component(.weekday, from: reminderTime) },
            set: { weekday in
                reminderTime = HabitReminderSchedule.replacingWeekday(
                    weekday,
                    in: reminderTime,
                    timeZoneIdentifier: sourceTimeZoneIdentifier
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
                reminderTime = HabitReminderSchedule.replacingMonthDay(
                    day,
                    in: reminderTime,
                    timeZoneIdentifier: sourceTimeZoneIdentifier
                )
            }
        )
    }

    private var sourceTimeZoneIdentifier: String {
        reminderCalendar.timeZone.identifier
    }

    private var reminderCalendar: Calendar {
        HabitReminderSchedule.calendar(timeZoneIdentifier: timeZoneIdentifier)
    }

    private var reminderSummary: String {
        HabitReminderSchedule.summary(
            frequency: frequency,
            reminderTime: reminderTime,
            timeZoneIdentifier: sourceTimeZoneIdentifier
        )
    }

    private func normalizeVisibleReminder() {
        guard hasReminderTime else { return }
        reminderTime = HabitReminderSchedule.normalizedReminderTime(
            reminderTime,
            frequency: frequency,
            timeZoneIdentifier: sourceTimeZoneIdentifier
        )
    }

    private func performScheduleTransition(_ updates: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth, updates)
    }

}
