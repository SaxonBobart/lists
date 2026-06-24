extension HabitFrequency {
    var habitDisplayName: String {
        switch self {
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
        case .custom:            return "Custom"
        }
    }
}
