import Foundation

enum ItemHierarchy {
    static func descendantIds(
        of parentId: UUID,
        in items: [Item],
        includingDeleted: Bool = false
    ) -> [UUID] {
        var out: [UUID] = []
        var stack: [UUID] = [parentId]
        var visited: Set<UUID> = [parentId]

        while let next = stack.popLast() {
            for child in items where child.parentId == next && (includingDeleted || child.deletedAt == nil) {
                guard visited.insert(child.id).inserted else { continue }
                out.append(child.id)
                stack.append(child.id)
            }
        }
        return out
    }

    static func selectedRoots(from ids: Set<UUID>, in items: [Item]) -> [UUID] {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

        return ids.filter { id in
            guard let item = byId[id] else { return false }
            return !ancestors(of: item, in: items).contains { ids.contains($0.id) }
        }
        .sorted { lhs, rhs in
            let left = byId[lhs]
            let right = byId[rhs]
            if left?.sortIndex != right?.sortIndex {
                return (left?.sortIndex ?? 0) < (right?.sortIndex ?? 0)
            }
            return lhs.uuidString < rhs.uuidString
        }
    }

    static func flattenForAll(
        parents: [Item],
        allItems: [Item],
        showCompleted: Bool,
        showPastEvents: Bool,
        lingering: Set<UUID> = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(item: Item, indent: Int)] {
        flatten(parents: parents, allItems: allItems) { item in
            item.deletedAt == nil
                && item.type != .habit
                && (showCompleted || !item.isComplete(at: now) || lingering.contains(item.id))
                && (showPastEvents || !item.isRolledOffPastEvent(now: now, calendar: calendar))
        }
    }

    static func flatten(
        parents: [Item],
        allItems: [Item],
        include: (Item) -> Bool
    ) -> [(item: Item, indent: Int)] {
        var output: [(Item, Int)] = []
        var visited = Set<UUID>()
        var stack = parents.reversed().map { ($0, 0) }

        while let (item, depth) = stack.popLast() {
            guard visited.insert(item.id).inserted else { continue }
            output.append((item, depth))

            let children = allItems
                .filter { $0.parentId == item.id && include($0) }
                .sorted { $0.sortIndex < $1.sortIndex }
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }
        return output
    }

    static func ancestors(of item: Item, in allItems: [Item]) -> [Item] {
        var chain: [Item] = []
        var parentId = item.parentId
        var visited: Set<UUID> = [item.id]

        while let id = parentId {
            guard visited.insert(id).inserted,
                  let parent = allItems.first(where: { $0.id == id && $0.deletedAt == nil }) else {
                break
            }
            chain.insert(parent, at: 0)
            parentId = parent.parentId
        }
        return chain
    }
}
