import SwiftUI

/// Existing scheduling bindings presented as compact values on the document.
struct DocumentScheduleProperties: View {
    let itemType: Item.ItemType
    @Binding var due: Date
    @Binding var end: Date
    @Binding var allDay: Bool
    @Binding var completable: Bool
    @Binding var hasDate: Bool
    @Binding var hasTime: Bool
    @Binding var reminder: Bool
    @Binding var alarm: Bool
    let timeZoneLabel: String
    let onShowTimeZone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if itemType == .event {
                DocumentPropertyRow(title: "Starts", systemImage: "calendar") {
                    DatePicker("Starts", selection: eventStart, displayedComponents: eventComponents)
                        .labelsHidden().datePickerStyle(.compact)
                        .accessibilityIdentifier("document.due")
                }
                DocumentPropertyRow(title: "Ends", systemImage: "calendar.badge.checkmark") {
                    DatePicker("Ends", selection: $end, in: due..., displayedComponents: eventComponents)
                        .labelsHidden().datePickerStyle(.compact)
                        .accessibilityIdentifier("document.ends")
                }
                DocumentPropertyToggle(title: "Completable", systemImage: "checkmark.circle", isOn: $completable, identifier: "document.completable")
                DocumentPropertyToggle(title: "All day", systemImage: "sun.max", isOn: $allDay, identifier: "document.allday")
            } else {
                DocumentPropertyRow(title: "Date", systemImage: "calendar") {
                    if hasDate {
                        HStack {
                            DatePicker("Date", selection: $due, displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.compact)
                                .accessibilityIdentifier("document.due")
                            Button { hasDate = false } label: { Image(systemName: "xmark.circle") }
                                .accessibilityLabel("Remove date")
                                .accessibilityIdentifier("document.due.remove")
                        }
                    } else {
                        Button("None") { hasDate = true }
                            .accessibilityLabel("Add date")
                            .accessibilityIdentifier("document.due")
                    }
                }
                DocumentPropertyRow(title: "Time", systemImage: "clock") {
                    if hasTime {
                        HStack {
                            DatePicker("Time", selection: $due, displayedComponents: .hourAndMinute)
                                .labelsHidden().datePickerStyle(.compact)
                                .accessibilityIdentifier("document.time")
                            Button { hasTime = false } label: { Image(systemName: "xmark.circle") }
                                .accessibilityLabel("Remove time")
                                .accessibilityIdentifier("document.time.remove")
                        }
                    } else {
                        Button("None") { hasTime = true }
                            .accessibilityLabel("Add time")
                            .accessibilityIdentifier("document.time")
                    }
                }
            }
            if hasTime {
                DocumentPropertyRow(title: "Time zone", systemImage: "globe") {
                    Button(timeZoneLabel, action: onShowTimeZone)
                        .accessibilityIdentifier("document.timezone")
                }
            }
            DocumentPropertyToggle(title: "Reminder", systemImage: "bell", isOn: $reminder, identifier: "document.reminder")
            DocumentPropertyToggle(title: "Alarm", systemImage: "alarm", isOn: $alarm, identifier: "document.alarm")
        }
    }

    private var eventComponents: DatePickerComponents { allDay ? [.date] : [.date, .hourAndMinute] }
    private var eventStart: Binding<Date> {
        Binding(get: { due }, set: { newStart in
            end = end.addingTimeInterval(newStart.timeIntervalSince(due))
            due = newStart
        })
    }
}

struct DocumentScheduleCard: View {
    let itemType: Item.ItemType
    @Binding var due: Date
    @Binding var end: Date
    @Binding var allDay: Bool
    var completable: Binding<Bool>? = nil
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
                    completable: completable,
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
