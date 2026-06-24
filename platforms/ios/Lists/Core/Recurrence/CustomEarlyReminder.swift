import Foundation

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
