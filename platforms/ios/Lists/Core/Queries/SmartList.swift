import Foundation

/// Built-in smart lists. See PRODUCT-SPEC.md §2.8.
public enum SmartList: String, CaseIterable, Identifiable, Sendable {
    case today
    case scheduled
    case all
    case completed
    case flagged
    case urgent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today:     return "Today"
        case .scheduled: return "Scheduled"
        case .all:       return "All"
        case .completed: return "Completed"
        case .flagged:   return "Flagged"
        case .urgent:    return "Urgent"
        }
    }

    public var iconName: String {
        switch self {
        case .today:     return "calendar"
        case .scheduled: return "clock"
        case .all:       return "tray.full"
        case .completed: return "checkmark.circle"
        case .flagged:   return "flag"
        case .urgent:    return "exclamationmark.triangle"
        }
    }

    /// Filter predicate. `now` is injectable for testing.
    public func matches(_ item: Item, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard item.parentId == nil || self != .all else { return true }
        // Visibility rule (PRODUCT-SPEC.md §2.5): "completed" is the only smart
        // list that surfaces ticked items. Everything else hides them.
        switch self {
        case .today:
            guard !item.done else { return false }
            guard let due = item.due else { return false }
            return calendar.isDate(due, inSameDayAs: now)
                || due < calendar.startOfDay(for: now)
        case .scheduled:
            guard !item.done else { return false }
            guard item.type != .habit else { return false }
            guard let due = item.due else { return false }
            return due >= calendar.startOfDay(for: now)
        case .all:
            guard !item.done else { return false }
            return item.type != .habit
        case .completed:
            return item.done
        case .flagged:
            return !item.done && item.flagged
        case .urgent:
            return !item.done && (item.triggers?.urgent?.enabled ?? false)
        }
    }
}
