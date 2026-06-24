import UIKit

extension ListDetailCollectionView.Coordinator {
    func canNestItem(_ sourceId: UUID, inside targetId: UUID) -> Bool {
        targetId != sourceId && !isDescendant(targetId, of: sourceId)
    }

    /// Resolves the new parentId for a gap drop based on the chosen indent
    /// and the row immediately above. Returns nil for top-level drops
    /// (`gap.indent == 0`) or when there is no row above.
    func computeNewParentId(for gap: ListDetailCollectionView.GapPosition,
                            sourceId: UUID) -> UUID? {
        guard gap.indent > 0, let parent else { return nil }
        let sectionId = ListDetailCollectionView.SectionKey.section(key: gap.sectionKey)
        let rows = dataSource.snapshot().itemIdentifiers(inSection: sectionId)
        var rowAbove: (id: UUID, depth: Int)?
        for row in rows {
            if case .item(let id, _) = row,
               let stop = gap.beforeRowId,
               id == stop {
                break
            }
            if case .item(let id, let indent) = row,
               id != sourceId,
               !isDescendant(id, of: sourceId) {
                rowAbove = (id, indent)
            }
        }
        guard let above = rowAbove else { return nil }
        let stepsUp = above.depth + 1 - gap.indent
        if stepsUp <= 0 { return above.id }
        var current: UUID? = above.id
        for _ in 0..<stepsUp {
            guard let id = current,
                  let item = parent.store.item(id) else {
                return nil
            }
            current = item.parentId
        }
        return current
    }

    func isDescendant(_ candidateId: UUID, of ancestorId: UUID) -> Bool {
        guard let parent else { return false }
        var current: UUID? = candidateId
        var visited: Set<UUID> = []
        while let id = current {
            if id == ancestorId { return true }
            guard visited.insert(id).inserted else { return false }
            current = parent.store.items.first(where: { $0.id == id })?.parentId
        }
        return false
    }

    func subtreeDepthOf(_ id: UUID) -> Int {
        guard let parent else { return 0 }
        var maxDepth = 0
        var queue: [(UUID, Int)] = [(id, 0)]
        var visited: Set<UUID> = []
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            let children = parent.store.items
                .filter { $0.parentId == current && $0.deletedAt == nil }
            for child in children {
                let childDepth = depth + 1
                maxDepth = max(maxDepth, childDepth)
                queue.append((child.id, childDepth))
            }
        }
        return maxDepth
    }
}
