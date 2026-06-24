import SwiftUI

struct QuickCaptureRepeatAndEarlySection: View {
    let repeatPresets: [RepeatPreset]
    @Binding var repeatPreset: RepeatPreset
    let repeatDisplay: String
    @Binding var endRepeatOn: Bool
    @Binding var endRepeatDate: Date
    let endRepeatSubtitle: String
    let hasReminder: Bool
    @Binding var earlyPreset: EarlyReminderPreset
    let earlyDisplay: String
    let onShowRepeatCustom: () -> Void
    let onShowEarlyCustom: () -> Void

    var body: some View {
        Section {
            Menu {
                ForEach(repeatPresets, id: \.self) { preset in
                    Button {
                        repeatPreset = preset
                        if preset == .custom {
                            onShowRepeatCustom()
                        }
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
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickcapture.repeat")

            if repeatPreset != .never {
                Toggle(isOn: $endRepeatOn) {
                    DetailFormRowLabel(
                        title: "End Repeat",
                        subtitle: endRepeatOn ? endRepeatSubtitle : nil,
                        systemImage: "calendar.badge.minus"
                    )
                }
                .tint(.green)
                .accessibilityIdentifier("quickcapture.repeat.end")

                if endRepeatOn {
                    DatePicker(
                        "",
                        selection: $endRepeatDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(.blue)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .accessibilityIdentifier("quickcapture.repeat.endDate")
                }
            }

            if hasReminder {
                Menu {
                    ForEach(EarlyReminderPreset.allCases, id: \.self) { preset in
                        Button {
                            earlyPreset = preset
                            if preset == .custom {
                                onShowEarlyCustom()
                            }
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
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickcapture.earlyReminder")
            }
        }
    }
}
