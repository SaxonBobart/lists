import Foundation

extension Array where Element == Item {
    /// Re-sorts items according to a user-chosen `SortMode`. `.manual`
    /// preserves the existing order; the other modes apply the named
    /// comparator (with a stable title tiebreaker for `.priority`).
    func sortedBy(_ mode: ListViewPreferences.SortMode) -> [Item] {
        switch mode {
        case .manual:
            // Drag-to-reorder writes a per-list dense sortIndex. Items that
            // pre-date the field (or have never been dragged) all sit at 0
            // and fall back to their incoming load order via Swift's stable
            // sort.
            return sorted { $0.sortIndex < $1.sortIndex }
        case .due:
            return sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        case .alphabetical:
            return sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .created:
            return sorted { $0.createdAt < $1.createdAt }
        case .priority:
            return sorted { lhs, rhs in
                let l = Self.priorityRank(lhs.priority)
                let r = Self.priorityRank(rhs.priority)
                if l != r { return l < r }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private static func priorityRank(_ p: Item.Priority) -> Int {
        switch p {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        case .none:   return 3
        }
    }
}
