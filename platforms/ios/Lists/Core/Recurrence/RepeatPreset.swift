import Foundation

// MARK: - Repeat preset

/// Unified preset list for the Repeat row. Task/note get the full set;
/// habits get the trimmed `.habitOptions` since the noisy cases (hourly,
/// weekdays, fortnightly, etc.) don't fit a "cycle + goal" model. `.custom`
/// is in both so the sub-sheet can compose richer RRULEs.
enum RepeatPreset: String, CaseIterable, Hashable {
    case never
    case hourly
    case daily
    case weekdays
    case weekends
    case weekly
    case fortnightly
    case monthly
    case everyThreeMonths
    case everySixMonths
    case yearly
    case custom

    var displayName: String {
        switch self {
        case .never:             return "Never"
        case .hourly:            return "Hourly"
        case .daily:             return "Daily"
        case .weekdays:          return "Weekdays"
        case .weekends:          return "Weekends"
        case .weekly:            return "Weekly"
        case .fortnightly:       return "Every 2 weeks"
        case .monthly:           return "Monthly"
        case .everyThreeMonths:  return "Every 3 months"
        case .everySixMonths:    return "Every 6 months"
        case .yearly:            return "Yearly"
        case .custom:            return "Custom…"
        }
    }

    /// RRULE for tasks/notes. `nil` means no recurrence.
    var rrule: String? {
        switch self {
        case .never:             return nil
        case .hourly:            return "FREQ=HOURLY"
        case .daily:             return "FREQ=DAILY"
        case .weekdays:          return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekends:          return "FREQ=WEEKLY;BYDAY=SA,SU"
        case .weekly:            return "FREQ=WEEKLY"
        case .fortnightly:       return "FREQ=WEEKLY;INTERVAL=2"
        case .monthly:           return "FREQ=MONTHLY"
        case .everyThreeMonths:  return "FREQ=MONTHLY;INTERVAL=3"
        case .everySixMonths:    return "FREQ=MONTHLY;INTERVAL=6"
        case .yearly:            return "FREQ=YEARLY"
        case .custom:            return nil   // handled via customRRule
        }
    }

    /// Habit frequency for the four habit-supported cases.
    var habitFrequency: HabitFrequency? {
        switch self {
        case .daily:   return .daily
        case .weekly:  return .weekly
        case .monthly: return .monthly
        case .custom:  return .custom
        default:       return nil
        }
    }

    /// Concise human label for an existing task RRULE: the matching preset's
    /// name when it maps to one ("Daily", "Every 6 months"), otherwise the
    /// custom summary ("Every 6 weeks"). Used by the row recurrence indicator.
    static func summary(forRRule rrule: String) -> String {
        if let preset = taskOptions.first(where: { $0.rrule == rrule }) {
            return preset.displayName
        }
        return RecurrenceRule.parse(rrule)?.shortLabel ?? "Custom"
    }

    static let taskOptions: [RepeatPreset] = [
        .never, .hourly, .daily, .weekdays, .weekends, .weekly,
        .fortnightly, .monthly, .everyThreeMonths, .everySixMonths, .yearly, .custom
    ]

    static let habitOptions: [RepeatPreset] = [.daily, .weekly, .monthly]
}
