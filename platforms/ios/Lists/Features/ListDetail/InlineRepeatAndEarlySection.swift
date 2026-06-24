import SwiftUI

struct InlineRepeatAndEarlySection: View {
    let availableRepeatPresets: [RepeatPreset]
    let currentRepeatDisplay: String
    let currentEarlyDisplay: String
    let endRepeatSubtitle: String
    let hasReminder: Bool

    @Binding var repeatPreset: RepeatPreset
    @Binding var endRepeatOn: Bool
    @Binding var endRepeatDate: Date
    @Binding var earlyPreset: EarlyReminderPreset
    @Binding var showRepeatCustom: Bool
    @Binding var showEarlyCustom: Bool

    var body: some View {
        Section {
            Menu {
                ForEach(availableRepeatPresets, id: \.self) { preset in
                    Button {
                        repeatPreset = preset
                        if preset == .custom { showRepeatCustom = true }
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
                    value: currentRepeatDisplay,
                    systemImage: repeatPreset == .never ? "repeat.badge.xmark" : "repeat"
                )
            }
            .buttonStyle(.plain)

            if repeatPreset != .never {
                Toggle(isOn: endRepeatBinding) {
                    DetailFormRowLabel(
                        title: "End Repeat",
                        subtitle: endRepeatOn ? endRepeatSubtitle : nil,
                        systemImage: "calendar.badge.minus"
                    )
                }
                .tint(.green)

                if endRepeatOn {
                    DatePicker("", selection: $endRepeatDate, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(.blue)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }
            }

            if hasReminder {
                Menu {
                    ForEach(EarlyReminderPreset.allCases, id: \.self) { preset in
                        Button {
                            earlyPreset = preset
                            if preset == .custom { showEarlyCustom = true }
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
                        value: currentEarlyDisplay,
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var endRepeatBinding: Binding<Bool> {
        Binding(
            get: { endRepeatOn },
            set: { value in withAnimation(.smooth) { endRepeatOn = value } }
        )
    }
}
