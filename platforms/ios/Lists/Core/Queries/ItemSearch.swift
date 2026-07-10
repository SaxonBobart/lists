import Foundation

enum ItemSearch {
    enum Scope {
        case fullText(String)
        case itemType(Item.ItemType)
        case hasTags
        case flagged
    }

    struct ListGroup: Equatable {
        let listName: String
        let items: [Item]
    }

    static func results(
        in items: [Item],
        scope: Scope,
        lingering: Set<UUID> = [],
        itemTypePolicy: ItemTypePolicy = .allEnabled,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Item] {
        let needle: String?
        switch scope {
        case .fullText(let query):
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return [] }
            needle = trimmed
        case .itemType, .hasTags, .flagged:
            needle = nil
        }

        return items.filter { item in
            let isLingering = lingering.contains(item.id)
            let isActive = !item.isComplete(at: now)
                && !item.isRolledOffPastEvent(now: now, calendar: calendar)
            guard item.deletedAt == nil, isLingering || isActive else {
                return false
            }
            guard item.isAvailable(in: itemTypePolicy) else { return false }

            switch scope {
            case .fullText:
                guard let needle else { return false }
                if item.title.lowercased().contains(needle) { return true }
                if item.body.lowercased().contains(needle) { return true }
                return item.tags.contains { $0.lowercased().contains(needle) }
            case .itemType(let type):
                return item.type == type
            case .hasTags:
                return !item.tags.isEmpty
            case .flagged:
                return item.flagged
            }
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
