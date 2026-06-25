import Foundation

/// Built-in smart lists. See `PRODUCT-SPEC.md` for product behavior.
public enum SmartList: String, CaseIterable, Identifiable, Sendable {
    case today
    case scheduled
    case all
    case completed
    case flagged
    case alarms
    case tags

    public var id: String { rawValue }

    public static func persistedValue(_ rawValue: String) -> SmartList? {
        rawValue == "urgent" ? .alarms : SmartList(rawValue: rawValue)
    }

    public var displayName: String {
        switch self {
        case .today:     return "Today"
        case .scheduled: return "Scheduled"
        case .all:       return "All"
        case .completed: return "Completed"
        case .flagged:   return "Flagged"
        case .alarms:    return "Alarms"
        case .tags:      return "Tags"
        }
    }

    public var iconName: String {
        switch self {
        case .today:     return "1.calendar"
        case .scheduled: return "calendar.badge.clock"
        case .all:       return "tray.full.fill"
        case .completed: return "checkmark"
        case .flagged:   return "flag.fill"
        case .alarms:    return "alarm.waves.left.and.right"
        case .tags:      return "number"
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
        // Sub-items get no unconditional pass for `.all`; they flow through the
        // same visibility rules as top-level items so counts match rendered rows.
        // Visibility rule: Completed is the only smart list that surfaces
        // finished items by default. Everything else hides them unless
        // `includeCompleted` is true.
        let completed = item.isComplete(at: now)
        switch self {
        case .today:
            guard let due = item.due else { return false }
            // A non-completable event has no overdue state: it shows in Today
            // on its day (or while a multi-day span overlaps today) and then
            // becomes the past — it must not linger like an overdue task.
            if item.type == .event && !item.completable {
                let today = calendar.startOfDay(for: now)
                let startsToday = calendar.isDate(due, inSameDayAs: now)
                let spansToday = due < today && (item.end.map { $0 > today } ?? false)
                return startsToday || spansToday
            }
            if completed {
                return includeCompleted && calendar.isDate(due, inSameDayAs: now)
            }
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
        case .alarms:
            guard includeCompleted || !completed else { return false }
            return item.triggers?.alarm?.enabled ?? false
        case .tags:
            // Not an item-filter list: Tags navigates to the Tags overview.
            // It never matches items directly.
            return false
        }
    }
}
