import SwiftUI

struct DocumentScheduleCard: View {
    let itemType: Item.ItemType
    @Binding var due: Date
    @Binding var end: Date
    @Binding var allDay: Bool
    @Binding var reminderEnabled: Bool
    @Binding var urgentEnabled: Bool
    @Binding var hasDate: Bool
    @Binding var hasTime: Bool
    let datePickerExpanded: Bool
    let timePickerExpanded: Bool
    let dateSubtitle: String?
    let timeSubtitle: String?
    let timeZoneLabel: String
    let onToggleDatePicker: () -> Void
    let onToggleTimePicker: () -> Void
    let onShowTimeZonePicker: () -> Void

    var body: some View {
        DocumentOptionsCard {
            if itemType == .event {
                EventDateRows(due: $due, end: $end, allDay: $allDay, idPrefix: "document")
            } else {
                taskDateRows
            }

            Divider()

            Toggle(isOn: $reminderEnabled) {
                DetailFormRowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)
            .padding(.vertical, 7)
            .accessibilityIdentifier("document.reminder")

            Divider()

            Toggle(isOn: $urgentEnabled) {
                DetailFormRowLabel(title: "Urgent", subtitle: nil, systemImage: "alarm.fill")
            }
            .tint(.green)
            .padding(.vertical, 7)
            .accessibilityIdentifier("document.urgent")
        }
    }

    @ViewBuilder
    private var taskDateRows: some View {
        DetailFormSplitToggleRow(
            title: "Date",
            subtitle: hasDate ? dateSubtitle : nil,
            systemImage: "calendar",
            isOn: $hasDate,
            tapTarget: hasDate ? onToggleDatePicker : nil,
            verticalPadding: 7
        )
        .accessibilityIdentifier("document.due")

        if hasDate && datePickerExpanded {
            DatePicker("Date", selection: $due, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.blue)
        }

        Divider()

        DetailFormSplitToggleRow(
            title: "Time",
            subtitle: hasTime ? timeSubtitle : nil,
            systemImage: "clock",
            isOn: $hasTime,
            tapTarget: hasTime ? onToggleTimePicker : nil,
            verticalPadding: 7
        )
        .accessibilityIdentifier("document.time")

        if hasTime && timePickerExpanded {
            DatePicker("Time", selection: $due, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(.blue)
                .frame(maxWidth: .infinity)

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
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("document.timezone")
        }
    }
}
