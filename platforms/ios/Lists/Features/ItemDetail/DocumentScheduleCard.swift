import SwiftUI

struct DocumentScheduleCard: View {
    let itemType: Item.ItemType
    @Binding var due: Date
    @Binding var end: Date
    @Binding var allDay: Bool
    @Binding var reminderEnabled: Bool
    @Binding var alarmEnabled: Bool
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
        Section {
            if itemType == .event {
                EventDateRows(
                    due: $due,
                    end: $end,
                    allDay: $allDay,
                    showsDividers: false,
                    idPrefix: "document"
                )
            } else {
                taskDateRows
            }

            Toggle(isOn: $reminderEnabled) {
                DetailFormRowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)
            .accessibilityIdentifier("document.reminder")

            Toggle(isOn: $alarmEnabled) {
                DetailFormRowLabel(title: "Alarm", subtitle: nil, systemImage: "alarm.waves.left.and.right")
            }
            .tint(.green)
            .accessibilityIdentifier("document.alarm")
        } header: {
            Text("Date and Time")
        }
    }

    @ViewBuilder
    private var taskDateRows: some View {
        DetailFormSplitToggleRow(
            title: "Date",
            subtitle: hasDate ? dateSubtitle : nil,
            systemImage: "calendar",
            isOn: $hasDate,
            tapTarget: hasDate ? onToggleDatePicker : nil
        )
        .accessibilityIdentifier("document.due")

        if hasDate && datePickerExpanded {
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
            tapTarget: hasTime ? onToggleTimePicker : nil
        )
        .accessibilityIdentifier("document.time")

        if hasTime && timePickerExpanded {
            DatePicker("Time", selection: $due, displayedComponents: .hourAndMinute)
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
            .accessibilityIdentifier("document.timezone")
        }
    }
}
