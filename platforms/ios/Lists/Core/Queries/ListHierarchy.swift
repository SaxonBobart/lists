import Foundation

enum ListHierarchy {
    struct FlatRow: Identifiable {
        let list: ItemList
        let depth: Int
        let hasChildren: Bool

        var id: String { list.id }
    }

    static func children(of parentId: String?, in lists: [ItemList]) -> [ItemList] {
        lists
            .filter { $0.parentId == parentId && $0.deletedAt == nil }
            .sorted { $0.position < $1.position }
    }

    static func flattenedRows(
        in lists: [ItemList],
        expanded: (String) -> Bool,
        excludingSubtree hiddenId: String? = nil
    ) -> [FlatRow] {
        var out: [FlatRow] = []

        func emit(_ list: ItemList, _ depth: Int) {
            if list.id == hiddenId { return }
            let kids = children(of: list.id, in: lists)
            out.append(FlatRow(list: list, depth: depth, hasChildren: !kids.isEmpty))
            guard !kids.isEmpty, expanded(list.id) else { return }
            for kid in kids { emit(kid, depth + 1) }
        }

        for root in children(of: nil, in: lists) {
            emit(root, 0)
        }
        return out
    }

    static func flattenedIds(in lists: [ItemList]) -> [String] {
        flattenedRows(in: lists, expanded: { _ in true }).map(\.id)
    }

    static func isDescendant(_ candidateId: String, of ancestorId: String, in lists: [ItemList]) -> Bool {
        var current: String? = candidateId
        var visited: Set<String> = []
        while let c = current {
            if c == ancestorId { return true }
            if !visited.insert(c).inserted { return false }
            current = lists.first(where: { $0.id == c })?.parentId
        }
        return false
    }

    static func depth(of id: String, in lists: [ItemList]) -> Int {
        var depth = 0
        var current: String? = id
        var visited: Set<String> = []
        while let c = current, visited.insert(c).inserted {
            guard let parentId = lists.first(where: { $0.id == c })?.parentId else { break }
            depth += 1
            current = parentId
        }
        return depth
    }

    static func subtreeDepth(of id: String, in lists: [ItemList]) -> Int {
        var maxDepth = 0
        var queue: [(String, Int)] = [(id, 0)]
        var visited: Set<String> = []
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            if !visited.insert(current).inserted { continue }
            for child in lists where child.parentId == current && child.deletedAt == nil {
                let childDepth = depth + 1
                if childDepth > maxDepth { maxDepth = childDepth }
                queue.append((child.id, childDepth))
            }
        }
        return maxDepth
    }

    static func canNest(
        _ sourceId: String,
        inside targetId: String,
        in lists: [ItemList],
        maxDepth: Int
    ) -> Bool {
        targetId != sourceId
            && !isDescendant(targetId, of: sourceId, in: lists)
            && (depth(of: targetId, in: lists) + subtreeDepth(of: sourceId, in: lists) + 1) <= maxDepth
    }

    static func descendantIds(
        of id: String,
        in lists: [ItemList],
        includingDeleted: Bool = false
    ) -> [String] {
        var out: [String] = []
        var stack: [String] = [id]
        var visited: Set<String> = [id]

        while let next = stack.popLast() {
            for child in lists where child.parentId == next && (includingDeleted || child.deletedAt == nil) {
                guard visited.insert(child.id).inserted else { continue }
                out.append(child.id)
                stack.append(child.id)
            }
        }
        return out
    }

    static func normalizedParentId(for list: ItemList, in lists: [ItemList]) -> String? {
        guard let parentId = list.parentId else { return nil }
        if parentId == list.id { return nil }
        guard let parent = lists.first(where: { $0.id == parentId }),
              parent.deletedAt == nil else { return nil }
        if Set(descendantIds(of: list.id, in: lists)).contains(parentId) { return nil }
        return parentId
    }

    static func invalidLoadedParent(
        _ parentId: String,
        for list: ItemList,
        in byId: [String: ItemList]
    ) -> Bool {
        if parentId == list.id { return true }
        guard let parent = byId[parentId] else { return true }
        if list.deletedAt == nil && parent.deletedAt != nil { return true }

        var seen: Set<String> = [list.id]
        var cursor: String? = parentId
        while let id = cursor {
            guard seen.insert(id).inserted else { return true }
            guard let ancestor = byId[id] else { return true }
            cursor = ancestor.parentId
        }
        return false
    }
}
