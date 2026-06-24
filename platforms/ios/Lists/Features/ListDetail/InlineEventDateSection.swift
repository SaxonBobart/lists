import SwiftUI

struct InlineEventDateSection: View {
    @Binding var due: Date
    @Binding var eventEnd: Date
    @Binding var allDay: Bool
    @Binding var hasTime: Bool
    @Binding var hasReminder: Bool
    @Binding var isUrgent: Bool

    var body: some View {
        Section {
            EventDateRows(due: $due, end: $eventEnd, allDay: $allDay, showsDividers: false)

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
}
