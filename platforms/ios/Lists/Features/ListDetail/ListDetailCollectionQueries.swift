import Foundation

extension ListDetailCollectionView {
    func sectionDisplayName(for key: String) -> String? {
        if key == listDetailUncategorizedKey {
            return (list?.sections.isEmpty == false) ? "Others" : nil
        }
        return list?.sections.first { $0.id.uuidString == key }?.name
    }

    func isOverdue(_ item: Item) -> Bool {
        item.isOverdue()
    }

    func applySort(_ items: [Item]) -> [Item] {
        items.sortedBy(prefs.sort(for: listId), direction: prefs.sortDirection(for: listId))
    }

    func sectionExpandedForRendering(
        _ key: String,
        showHeader: Bool,
        draggingKey: String? = nil
    ) -> Bool {
        let userExpanded = showHeader ? prefs.sectionExpanded(key, in: listId) : true
        let expanded = moveSession.isActive || userExpanded
        return expanded && key != draggingKey
    }

    func flattenWithChildren(_ parents: [Item],
                             draggingItemId: UUID? = nil,
                             forceExpanded: Bool = false) -> [(item: Item, indent: Int)] {
        var out: [(Item, Int)] = []
        let showCompleted = prefs.showCompleted(for: listId)
        let showPastEvents = prefs.showPastEvents(for: listId)
        let lingering = lingeringIds
        let now = Date.now
        let calendar = Calendar.current
        let isChildVisible: (Item) -> Bool = { item in
            item.deletedAt == nil
                && (showCompleted || !item.isComplete(at: now) || lingering.contains(item.id))
                && (showPastEvents || !item.isRolledOffPastEvent(now: now, calendar: calendar))
        }
        // Iterative DFS handles arbitrary depth and terminates if corrupt data
        // accidentally creates a parent cycle.
        var visited = Set<UUID>()
        var stack = parents
            .filter { $0.id != draggingItemId }
            .reversed()
            .map { ($0, 0) }
        while let (item, depth) = stack.popLast() {
            guard !visited.contains(item.id) else { continue }
            visited.insert(item.id)
            out.append((item, depth))
            guard forceExpanded || prefs.itemExpanded(item.id.uuidString, in: listId) else { continue }
            let children = store.items
                .filter { $0.parentId == item.id && isChildVisible($0) && $0.id != draggingItemId }
                .sorted { $0.sortIndex < $1.sortIndex }
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }
        return out
    }
}
