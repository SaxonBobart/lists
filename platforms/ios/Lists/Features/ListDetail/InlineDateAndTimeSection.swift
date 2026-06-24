import SwiftUI

struct InlineDateAndTimeSection: View {
    @Binding var hasDate: Bool
    @Binding var due: Date
    @Binding var hasTime: Bool
    @Binding var hasReminder: Bool
    @Binding var isUrgent: Bool
    @Binding var dueTimeZone: String?
    @Binding var expandedPicker: InlineDateTimeExpandedPicker

    let dateSubtitle: String
    let timeSubtitle: String
    let onShowTimeZonePicker: () -> Void

    var body: some View {
        Section {
            DetailFormSplitToggleRow(
                title: "Date",
                subtitle: hasDate ? dateSubtitle : nil,
                systemImage: "calendar",
                isOn: $hasDate,
                tapTarget: hasDate ? { toggleDatePicker() } : nil
            )

            if hasDate && expandedPicker == .date {
                DatePicker("Date", selection: $due, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(.blue)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }

            DetailFormSplitToggleRow(
                title: "Time",
                subtitle: hasTime ? timeSubtitle : nil,
                systemImage: "clock",
                isOn: $hasTime,
                tapTarget: hasTime ? { toggleTimePicker() } : nil
            )

            if hasTime && expandedPicker == .time {
                DatePicker("Time", selection: $due, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(.blue)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                Button(action: onShowTimeZonePicker) {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        Text("Time Zone").foregroundStyle(.primary)
                        Spacer()
                        Text(TimeZoneLabel.display(for: dueTimeZone)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                            .font(.footnote)
                    }
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $hasReminder) {
                DetailFormRowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)

            Toggle(isOn: urgentBinding) {
                DetailFormRowLabel(title: "Urgent", subtitle: nil, systemImage: "alarm.fill")
            }
            .tint(.green)
        } header: {
            Text("Date and Time")
        }
    }

    private var urgentBinding: Binding<Bool> {
        Binding(
            get: { isUrgent },
            set: { value in
                withAnimation(.smooth) {
                    isUrgent = value
                    if value {
                        if !hasReminder { hasReminder = true }
                        if !hasTime { hasTime = true }
                    }
                }
            }
        )
    }

    private func toggleDatePicker() {
        withAnimation(.smooth) {
            expandedPicker = expandedPicker == .date ? .none : .date
        }
    }

    private func toggleTimePicker() {
        withAnimation(.smooth) {
            expandedPicker = expandedPicker == .time ? .none : .time
        }
    }
}
