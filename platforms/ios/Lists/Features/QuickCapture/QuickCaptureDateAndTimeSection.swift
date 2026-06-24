import SwiftUI

struct QuickCaptureDateAndTimeSection: View {
    let selectedType: Item.ItemType
    @Binding var due: Date
    @Binding var endDate: Date
    @Binding var allDay: Bool
    @Binding var hasDate: Bool
    @Binding var hasTime: Bool
    @Binding var hasReminder: Bool
    @Binding var isUrgent: Bool
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

            Toggle(isOn: $isUrgent) {
                DetailFormRowLabel(title: "Urgent", subtitle: nil, systemImage: "alarm.fill")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.urgent")
        } header: {
            Text("Date and Time")
        } footer: {
            Text("Urgent items appear in the Urgent list and use the reminder time.")
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
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

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
