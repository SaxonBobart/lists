import SwiftUI

struct DocumentRepeatCard: View {
    let repeatPreset: RepeatPreset
    let repeatDisplay: String
    let repeatUntil: Date?
    let reminderEnabled: Bool
    let earlyPreset: EarlyReminderPreset
    let earlyDisplay: String
    @Binding var endRepeat: Bool
    @Binding var endRepeatDate: Date
    let onSelectRepeat: (RepeatPreset) -> Void
    let onSelectEarly: (EarlyReminderPreset) -> Void

    var body: some View {
        DocumentOptionsCard {
            Menu {
                ForEach(RepeatPreset.taskOptions, id: \.self) { preset in
                    Button {
                        onSelectRepeat(preset)
                    } label: {
                        if preset == repeatPreset {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                }
            } label: {
                DetailFormPickerRowLabel(
                    title: "Repeat",
                    value: repeatDisplay,
                    systemImage: repeatPreset == .never ? "repeat.badge.xmark" : "repeat"
                )
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.repeat")

            if repeatPreset != .never {
                Divider()
                Toggle(isOn: $endRepeat) {
                    DetailFormRowLabel(
                        title: "End Repeat",
                        subtitle: repeatUntil.map(ScheduleFormatting.longDate),
                        systemImage: "calendar.badge.minus"
                    )
                }
                .tint(.green)
                .padding(.vertical, 7)
                .accessibilityIdentifier("document.repeat.end")

                if repeatUntil != nil {
                    DatePicker(
                        "",
                        selection: $endRepeatDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(.blue)
                    .accessibilityIdentifier("document.repeat.endDate")
                }
            }

            if reminderEnabled {
                Divider()
                Menu {
                    ForEach(EarlyReminderPreset.allCases, id: \.self) { preset in
                        Button {
                            onSelectEarly(preset)
                        } label: {
                            if preset == earlyPreset {
                                Label(preset.displayName, systemImage: "checkmark")
                            } else {
                                Text(preset.displayName)
                            }
                        }
                    }
                } label: {
                    DetailFormPickerRowLabel(
                        title: "Early Reminder",
                        value: earlyDisplay,
                        systemImage: "clock.arrow.circlepath"
                    )
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("document.earlyReminder")
            }
        }
    }

}
