import Foundation

// MARK: - Early reminder preset

/// Preset offsets for the Early Reminder row, matching PRODUCT-SPEC §4.1.1.
enum EarlyReminderPreset: String, CaseIterable, Hashable {
    case none
    case fiveMin
    case fifteenMin
    case thirtyMin
    case oneHour
    case twoHours
    case oneDay
    case twoDays
    case oneWeek
    case oneMonth
    case custom

    var displayName: String {
        switch self {
        case .none:       return "None"
        case .fiveMin:    return "5 minutes before"
        case .fifteenMin: return "15 minutes before"
        case .thirtyMin:  return "30 minutes before"
        case .oneHour:    return "1 hour before"
        case .twoHours:   return "2 hours before"
        case .oneDay:     return "1 day before"
        case .twoDays:    return "2 days before"
        case .oneWeek:    return "1 week before"
        case .oneMonth:   return "1 month before"
        case .custom:     return "Custom…"
        }
    }

    var value: EarlyReminder? {
        switch self {
        case .none:       return nil
        case .fiveMin:    return EarlyReminder(value: 5, unit: .minute)
        case .fifteenMin: return EarlyReminder(value: 15, unit: .minute)
        case .thirtyMin:  return EarlyReminder(value: 30, unit: .minute)
        case .oneHour:    return EarlyReminder(value: 1, unit: .hour)
        case .twoHours:   return EarlyReminder(value: 2, unit: .hour)
        case .oneDay:     return EarlyReminder(value: 1, unit: .day)
        case .twoDays:    return EarlyReminder(value: 2, unit: .day)
        case .oneWeek:    return EarlyReminder(value: 1, unit: .week)
        case .oneMonth:   return EarlyReminder(value: 1, unit: .month)
        case .custom:     return nil   // handled via customEarly
        }
    }
}
