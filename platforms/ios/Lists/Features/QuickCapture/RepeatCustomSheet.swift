import SwiftUI

/// Sub-sheet for building a custom Repeat rule: `Every N day/week/month/year`.
/// End Repeat is handled by a separate row in QuickCaptureSheet so it works
/// for preset cadences as well as custom ones.
struct RepeatCustomSheet: View {
    let initialInterval: Int
    let initialUnit: RepeatCustomUnit
    let onApply: (Int, RepeatCustomUnit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var interval: Int
    @State private var unit: RepeatCustomUnit

    init(
        initialInterval: Int = 1,
        initialUnit: RepeatCustomUnit = .week,
        onApply: @escaping (Int, RepeatCustomUnit) -> Void
    ) {
        self.initialInterval = initialInterval
        self.initialUnit = initialUnit
        self.onApply = onApply
        _interval = State(initialValue: initialInterval)
        _unit = State(initialValue: initialUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $interval, in: 1...99) {
                        HStack {
                            Text("Every")
                            Spacer()
                            Text("\(interval) \(unit.displayName(plural: interval > 1))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker(selection: $unit) {
                        ForEach(RepeatCustomUnit.allCases, id: \.self) { u in
                            Text(u.displayName(plural: true).capitalized).tag(u)
                        }
                    } label: {
                        Text("Unit")
                    }
                }
            }
            .navigationTitle("Custom Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Cancel")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onApply(interval, unit)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Apply")
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

/// Unit options for a Custom Repeat rule. Maps to RFC 5545 FREQ values.
enum RepeatCustomUnit: String, CaseIterable, Hashable {
    case day, week, month, year

    func displayName(plural: Bool) -> String {
        switch self {
        case .day:   return plural ? "days" : "day"
        case .week:  return plural ? "weeks" : "week"
        case .month: return plural ? "months" : "month"
        case .year:  return plural ? "years" : "year"
        }
    }

    var rruleFreq: String {
        switch self {
        case .day:   return "DAILY"
        case .week:  return "WEEKLY"
        case .month: return "MONTHLY"
        case .year:  return "YEARLY"
        }
    }
}

/// Build an RFC 5545 RRULE from the custom-repeat inputs.
enum CustomRRule {
    static func make(interval: Int, unit: RepeatCustomUnit, end: Date?) -> String {
        var parts = ["FREQ=\(unit.rruleFreq)", "INTERVAL=\(max(1, interval))"]
        if let end {
            parts.append("UNTIL=\(format(end))")
        }
        return parts.joined(separator: ";")
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// Best-effort parse of an RRULE into `(interval, unit, end)`. Returns nil
    /// when the RRULE doesn't match a supported `FREQ=...;INTERVAL=...` shape.
    static func parse(_ rrule: String) -> (interval: Int, unit: RepeatCustomUnit, end: Date?)? {
        let parts = Dictionary(uniqueKeysWithValues: rrule
            .split(separator: ";")
            .compactMap { part -> (String, String)? in
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0], kv[1]) : nil
            })
        guard let freq = parts["FREQ"] else { return nil }
        let unit: RepeatCustomUnit
        switch freq {
        case "DAILY":   unit = .day
        case "WEEKLY":  unit = .week
        case "MONTHLY": unit = .month
        case "YEARLY":  unit = .year
        default: return nil
        }
        let interval = Int(parts["INTERVAL"] ?? "1") ?? 1
        let end: Date? = parts["UNTIL"].flatMap { raw in
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            f.timeZone = TimeZone(identifier: "UTC")
            return f.date(from: raw)
        }
        return (interval, unit, end)
    }

    /// Human-readable label for the Repeat row, derived from a custom RRULE.
    static func displayName(for rrule: String?) -> String {
        guard let rrule, let parsed = parse(rrule) else { return "Custom…" }
        let unitName = parsed.unit.displayName(plural: parsed.interval > 1)
        let core = parsed.interval == 1 ? "Every \(unitName)" : "Every \(parsed.interval) \(unitName)"
        return core
    }
}
