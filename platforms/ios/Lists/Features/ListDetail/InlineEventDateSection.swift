import SwiftUI

struct InlineEventDateSection: View {
    @Binding var due: Date
    @Binding var eventEnd: Date
    @Binding var allDay: Bool
    @Binding var hasTime: Bool
    @Binding var hasReminder: Bool
    @Binding var hasAlarm: Bool

    var body: some View {
        Section {
            EventDateRows(due: $due, end: $eventEnd, allDay: $allDay, showsDividers: false)

            Toggle(isOn: $hasReminder) {
                DetailFormRowLabel(title: "Reminder", subtitle: nil, systemImage: "bell")
            }
            .tint(.green)

            Toggle(isOn: alarmBinding) {
                DetailFormRowLabel(title: "Alarm", subtitle: nil, systemImage: "alarm.waves.left.and.right")
            }
            .tint(.green)
        } header: {
            Text("Date and Time")
        }
    }

    private var alarmBinding: Binding<Bool> {
        Binding(
            get: { hasAlarm },
            set: { value in
                withAnimation(.smooth) {
                    hasAlarm = value
                    if value {
                        if !hasReminder { hasReminder = true }
                        if !hasTime { hasTime = true }
                    }
                }
            }
        )
    }
}
