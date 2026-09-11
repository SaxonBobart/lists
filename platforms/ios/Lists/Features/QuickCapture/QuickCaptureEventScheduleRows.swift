import SwiftUI

struct QuickCaptureEventScheduleRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var due: Date
    @Binding var endDate: Date
    @Binding var allDay: Bool
    var completable: Binding<Bool>? = nil

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

        if let completable {
            Toggle(isOn: completable) {
                DetailFormRowLabel(title: "Completable", subtitle: nil, systemImage: "checkmark.circle")
            }
            .tint(.green)
            .accessibilityIdentifier("quickcapture.completable")
        }

        Toggle(isOn: allDayBinding) {
            DetailFormRowLabel(title: "All Day", subtitle: nil, systemImage: "calendar")
        }
        .tint(.green)
        .accessibilityIdentifier("quickcapture.allday")
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { allDay },
            set: { newValue in
                withAnimation(reduceMotion ? nil : .smooth) {
                    allDay = newValue
                }
            }
        )
    }
}
