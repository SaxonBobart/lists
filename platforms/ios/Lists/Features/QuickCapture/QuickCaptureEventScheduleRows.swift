import SwiftUI

struct QuickCaptureEventScheduleRows: View {
    @Binding var due: Date
    @Binding var endDate: Date
    @Binding var allDay: Bool

    var body: some View {
        DatePicker(
            selection: $due,
            displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
        ) {
            Text("Starts")
        }
        .tint(ListsTokens.accent)
        .accessibilityIdentifier("quickcapture.due")

        DatePicker(
            selection: $endDate,
            in: due...,
            displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
        ) {
            Text("Ends")
        }
        .tint(ListsTokens.accent)
        .accessibilityIdentifier("quickcapture.ends")

        Toggle(isOn: allDayBinding) {
            DetailFormRowLabel(title: "All Day", subtitle: nil, systemImage: "calendar")
        }
        .tint(.green)
        .accessibilityIdentifier("quickcapture.allday")
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { allDay },
            set: { newValue in withAnimation(.smooth) { allDay = newValue } }
        )
    }
}
