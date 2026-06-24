import SwiftUI

/// Mirrors `HabitDetailView`'s Details tab: one Habit section with Frequency,
/// Flexible goal, Goal per cycle, Reminder + time, and Show streak.
struct QuickCaptureHabitSection: View {
    @Binding var frequency: HabitFrequency
    @Binding var goalPerCycle: Int
    @Binding var flexibleGoal: Bool
    @Binding var hasReminderTime: Bool
    @Binding var reminderTime: Date
    @Binding var showStreak: Bool

    var body: some View {
        Section("Habit") {
            Picker(selection: $frequency) {
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
                DetailFormRowLabel(title: "Flexible goal", subtitle: nil, systemImage: "calendar.badge.clock")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.habit.flexibleGoal")

            Stepper(value: $goalPerCycle, in: 1...99) {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text(goalStepperLabel)
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
                DatePicker(
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                ) {
                    Label("Time", systemImage: "clock")
                        .labelStyle(GlyphLabelStyle())
                }
                .accessibilityIdentifier("quickcapture.habit.reminderTime")
            }

            Toggle(isOn: $showStreak) {
                DetailFormRowLabel(title: "Show streak", subtitle: nil, systemImage: "flame")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.habit.showStreak")
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { hasReminderTime },
            set: { newValue in
                withAnimation(.smooth) { hasReminderTime = newValue }
            }
        )
    }

    private var goalStepperLabel: String {
        guard flexibleGoal else { return "Goal per cycle" }
        return "Times \(HabitStats.cycleNoun(for: frequency))"
    }

}
