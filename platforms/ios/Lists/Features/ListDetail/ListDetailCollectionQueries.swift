import Foundation

extension ListDetailCollectionView {
    func sectionDisplayName(for key: String) -> String? {
        if key == listDetailUncategorizedKey {
            return (list?.sections.isEmpty == false) ? "Others" : nil
        }
        return list?.sections.first { $0.id.uuidString == key }?.name
    }

    var renderedSectionKeys: [String] {
        guard let list else { return [] }
        let showCompleted = prefs.showCompleted(for: listId)
        let showPastEvents = prefs.showPastEvents(for: listId)
        let now = Date.now
        let calendar = Calendar.current
        let visibleParents = store.items.filter { item in
            item.listId == listId
                && item.deletedAt == nil
                && item.parentId == nil
                && item.isAvailable(habitsEnabled: habitsPluginEnabled)
                && !moveSession.isMoving(item.id)
                && (showCompleted || !item.isComplete(at: now) || lingeringIds.contains(item.id))
                && (showPastEvents || !item.isRolledOffPastEvent(now: now, calendar: calendar))
        }
        let namedKeys = list.sections
            .sorted { $0.position < $1.position }
            .map(\.id.uuidString)
        let namedKeysSet = Set(namedKeys)
        let hasUncategorized = visibleParents.contains { item in
            guard let section = item.section else { return true }
            return namedKeysSet.contains(section) == false
        }
        if namedKeys.isEmpty {
            return hasUncategorized ? [listDetailUncategorizedKey] : []
        }
        return namedKeys + (hasUncategorized ? [listDetailUncategorizedKey] : [])
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
                && item.isAvailable(habitsEnabled: habitsPluginEnabled)
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
