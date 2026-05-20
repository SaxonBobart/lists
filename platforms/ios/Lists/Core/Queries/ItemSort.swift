import Foundation

extension Array where Element == Item {
    /// Re-sorts items according to a user-chosen `SortMode`. `.manual`
    /// preserves the existing order; the other modes apply the named
    /// comparator (with a stable title tiebreaker for `.priority`).
    func sortedBy(
        _ mode: ListViewPreferences.SortMode,
        direction: ListViewPreferences.SortDirection = .ascending
    ) -> [Item] {
        let ascending: [Item]
        switch mode {
        case .manual:
            // Manual drag order — direction is ignored.
            return sorted { $0.sortIndex < $1.sortIndex }
        case .due:
            ascending = sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        case .alphabetical:
            ascending = sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .created:
            ascending = sorted { $0.createdAt < $1.createdAt }
        case .priority:
            ascending = sorted { lhs, rhs in
                let l = Self.priorityRank(lhs.priority)
                let r = Self.priorityRank(rhs.priority)
                if l != r { return l < r }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        return direction == .descending ? ascending.reversed() : ascending
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
