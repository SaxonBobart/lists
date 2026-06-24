import Foundation

enum ItemSearch {
    struct ListGroup: Equatable {
        let listName: String
        let items: [Item]
    }

    static func results(
        matching query: String,
        in items: [Item],
        lingering: Set<UUID> = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Item] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        return items.filter { item in
            let isLingering = lingering.contains(item.id)
            let isActive = !item.isComplete(at: now)
                && !item.isRolledOffPastEvent(now: now, calendar: calendar)
            guard item.deletedAt == nil, isLingering || isActive else {
                return false
            }
            if item.title.lowercased().contains(needle) { return true }
            if item.body.lowercased().contains(needle) { return true }
            return item.tags.contains { $0.lowercased().contains(needle) }
        }
    }

    static func groupedByList(_ results: [Item], lists: [ItemList]) -> [ListGroup] {
        let nameById = Dictionary(lists.map { ($0.id, $0.name) }, uniquingKeysWith: { _, new in new })
        let grouped = Dictionary(grouping: results) { item in
            nameById[item.listId] ?? item.listId
        }
        return grouped
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { listName, items in
                ListGroup(
                    listName: listName,
                    items: items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                )
            }
    }
}
