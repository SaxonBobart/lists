import Foundation

/// Built-in smart lists. See PRODUCT-SPEC.md §2.8.
public enum SmartList: String, CaseIterable, Identifiable, Sendable {
    case today
    case scheduled
    case all
    case completed
    case flagged
    case urgent
    case tags
    case assigned

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today:     return "Today"
        case .scheduled: return "Scheduled"
        case .all:       return "All"
        case .completed: return "Completed"
        case .flagged:   return "Flagged"
        case .urgent:    return "Urgent"
        case .tags:      return "Tags"
        case .assigned:  return "Assigned"
        }
    }

    public var iconName: String {
        switch self {
        case .today:     return "1.calendar"
        case .scheduled: return "calendar.badge.clock"
        case .all:       return "tray.full.fill"
        case .completed: return "checkmark"
        case .flagged:   return "flag.fill"
        case .urgent:    return "alarm.fill"
        case .tags:      return "number"
        case .assigned:  return "person.fill"
        }
    }

    /// Filter predicate. `now` is injectable for testing. Set
    /// `includeCompleted` to keep complete items in non-Completed lists —
    /// used by the per-list "Show Completed" toggle.
    public func matches(
        _ item: Item,
        now: Date = .now,
        includeCompleted: Bool = false,
        calendar: Calendar = .current
    ) -> Bool {
        // Soft-deleted items live in Recently Deleted; they never appear in
        // any built-in smart list, including Completed.
        guard item.deletedAt == nil else { return false }
        guard item.parentId == nil || self != .all else { return true }
        // Visibility rule (PRODUCT-SPEC.md §2.5): "completed" is the only smart
        // list that surfaces ticked items by default. Everything else hides
        // them unless `includeCompleted` is true.
        let completed = item.isComplete
        switch self {
        case .today:
            guard includeCompleted || !completed else { return false }
            guard let due = item.due else { return false }
            return calendar.isDate(due, inSameDayAs: now)
                || due < calendar.startOfDay(for: now)
        case .scheduled:
            guard includeCompleted || !completed else { return false }
            guard item.type != .habit else { return false }
            guard let due = item.due else { return false }
            return due >= calendar.startOfDay(for: now)
        case .all:
            guard includeCompleted || !completed else { return false }
            return item.type != .habit
        case .completed:
            return completed
        case .flagged:
            guard includeCompleted || !completed else { return false }
            return item.flagged
        case .urgent:
            guard includeCompleted || !completed else { return false }
            return item.triggers?.urgent?.enabled ?? false
        case .tags, .assigned:
            // Not item-filter lists: Tags navigates to the Tags overview and
            // Assigned is a placeholder. They never match items directly.
            return false
        }
    }
}
