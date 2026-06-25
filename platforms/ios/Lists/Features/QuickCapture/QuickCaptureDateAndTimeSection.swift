import SwiftUI

struct QuickCaptureDateAndTimeSection: View {
    let selectedType: Item.ItemType
    @Binding var due: Date
    @Binding var endDate: Date
    @Binding var allDay: Bool
    @Binding var hasDate: Bool
    @Binding var hasTime: Bool
    @Binding var hasReminder: Bool
    @Binding var hasAlarm: Bool
    let datePickerExpanded: Bool
    let timePickerExpanded: Bool
    let dateSubtitle: String
    let timeSubtitle: String
    let timeZoneLabel: String
    let onToggleDatePicker: () -> Void
    let onToggleTimePicker: () -> Void
    let onShowTimeZonePicker: () -> Void

    var body: some View {
        Section {
            if selectedType == .event {
                QuickCaptureEventScheduleRows(
                    due: $due,
                    endDate: $endDate,
                    allDay: $allDay
                )
            } else {
                taskDateAndTimeRows
            }

            Toggle(isOn: $hasReminder) {
                DetailFormRowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.reminder")

            Toggle(isOn: $hasAlarm) {
                DetailFormRowLabel(title: "Alarm", subtitle: nil, systemImage: "alarm.waves.left.and.right")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.alarm")
        } header: {
            Text("Date and Time")
        }
    }

    @ViewBuilder
    private var taskDateAndTimeRows: some View {
        DetailFormSplitToggleRow(
            title: "Date",
            subtitle: hasDate ? dateSubtitle : nil,
            systemImage: "calendar",
            isOn: $hasDate,
            tapTarget: hasDate ? onToggleDatePicker : nil
        )
        .accessibilityIdentifier("quickcapture.due")

        if hasDate && datePickerExpanded {
            DatePicker(
                "Date",
                selection: $due,
                displayedComponents: .date
            )
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
            tapTarget: hasTime ? onToggleTimePicker : nil
        )
        .accessibilityIdentifier("quickcapture.time")

        if hasTime && timePickerExpanded {
            DatePicker(
                "Time",
                selection: $due,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(.blue)
            .frame(maxWidth: .infinity, alignment: .center)
            .clipped()
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

            Button {
                onShowTimeZonePicker()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text("Time Zone")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(timeZoneLabel)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .font(.footnote)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickcapture.timezone")
        }
    }
}
