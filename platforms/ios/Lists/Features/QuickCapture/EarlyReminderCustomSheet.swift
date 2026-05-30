import SwiftUI

/// Sub-sheet for building a custom Early Reminder offset (e.g. "7 minutes
/// before"). On `Done`, hands the chosen `(value, unit)` back to the caller.
struct EarlyReminderCustomSheet: View {
    let initialValue: Int
    let initialUnit: EarlyReminder.Unit
    let onApply: (Int, EarlyReminder.Unit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Int
    @State private var unit: EarlyReminder.Unit

    init(
        initialValue: Int = 5,
        initialUnit: EarlyReminder.Unit = .minute,
        onApply: @escaping (Int, EarlyReminder.Unit) -> Void
    ) {
        self.initialValue = initialValue
        self.initialUnit = initialUnit
        self.onApply = onApply
        _value = State(initialValue: initialValue)
        _unit = State(initialValue: initialUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $value, in: 1...99) {
                        HStack {
                            Text("Remind")
                            Spacer()
                            Text("\(value) \(unitName(for: unit, plural: value > 1)) before")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker(selection: $unit) {
                        ForEach(EarlyReminder.Unit.allCases, id: \.self) { u in
                            Text(unitName(for: u, plural: true).capitalized).tag(u)
                        }
                    } label: {
                        Text("Unit")
                    }
                }
            }
            .navigationTitle("Custom Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onApply(value, unit)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Apply")
                    }
                    .tint(.primary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func unitName(for unit: EarlyReminder.Unit, plural: Bool) -> String {
        switch unit {
        case .minute: return plural ? "minutes" : "minute"
        case .hour:   return plural ? "hours" : "hour"
        case .day:    return plural ? "days" : "day"
        case .week:   return plural ? "weeks" : "week"
        case .month:  return plural ? "months" : "month"
        }
    }
}

/// Human-readable label for the Early Reminder row, derived from an EarlyReminder.
enum CustomEarlyReminder {
    static func displayName(for early: EarlyReminder?) -> String {
        guard let early else { return "Custom…" }
        let plural = early.value > 1
        let unitName: String
        switch early.unit {
        case .minute: unitName = plural ? "minutes" : "minute"
        case .hour:   unitName = plural ? "hours" : "hour"
        case .day:    unitName = plural ? "days" : "day"
        case .week:   unitName = plural ? "weeks" : "week"
        case .month:  unitName = plural ? "months" : "month"
        }
        return "\(early.value) \(unitName) before"
    }
}
