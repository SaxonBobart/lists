import SwiftUI

struct EventDateRows: View {
    @Binding var due: Date
    @Binding var end: Date
    @Binding var allDay: Bool
    var showsDividers: Bool = true
    var idPrefix: String = "event"

    private var components: DatePickerComponents {
        allDay ? [.date] : [.date, .hourAndMinute]
    }

    var body: some View {
        Group {
            HStack {
                Text("Starts").foregroundStyle(.primary)
                Spacer(minLength: 12)
                DatePicker("", selection: startBinding, displayedComponents: components)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(ListsTokens.accent)
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("\(idPrefix).due")

            if showsDividers { Divider() }

            HStack {
                Text("Ends").foregroundStyle(.primary)
                Spacer(minLength: 12)
                DatePicker("", selection: $end, in: due..., displayedComponents: components)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(ListsTokens.accent)
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("\(idPrefix).ends")

            if showsDividers { Divider() }

            Toggle(isOn: $allDay) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                    Text("All Day")
                }
            }
            .tint(.green)
            .padding(.vertical, 7)
            .accessibilityIdentifier("\(idPrefix).allday")
        }
    }

    /// Moving the start keeps the event's duration; the end shifts by the same
    /// delta whether the host uses local state or a live-applying store binding.
    private var startBinding: Binding<Date> {
        Binding(
            get: { due },
            set: { newStart in
                end = end.addingTimeInterval(newStart.timeIntervalSince(due))
                due = newStart
            }
        )
    }
}
