import UIKit

extension ListDetailCollectionView.Coordinator {
    func currentIndexPath(forItemId id: UUID) -> IndexPath? {
        let snap = dataSource.snapshot()
        for row in snap.itemIdentifiers {
            if case .item(let rid, let indent) = row, rid == id {
                return dataSource.indexPath(for: .item(id: rid, indent: indent))
            }
        }
        return nil
    }

    @discardableResult
    func performItemReorder(itemId: UUID, dropTarget: ListDetailCollectionView.ItemDropTarget) -> Bool {
        guard let parent = parent else { return false }
        let snap = dataSource.snapshot()
        guard let item = parent.store.items.first(where: { $0.id == itemId }) else { return false }

        enum InsertPlacement {
            case end
            case before(UUID)
            case after(UUID)
            case inside(UUID)
        }

        let sectionKey: String
        let newParentId: UUID?
        let placement: InsertPlacement

        switch dropTarget {
        case .nestInto(let targetId):
            guard canNestItem(itemId, inside: targetId),
                  let target = parent.store.items.first(where: { $0.id == targetId && $0.deletedAt == nil }) else {
                return false
            }
            sectionKey = target.section ?? listDetailUncategorizedKey
            newParentId = target.id
            placement = .inside(target.id)
        case .gap(let gap):
            sectionKey = gap.sectionKey
            newParentId = computeNewParentId(for: gap, sourceId: itemId)
            if let beforeId = gap.beforeRowId {
                guard beforeId != itemId, !isDescendant(beforeId, of: itemId) else {
                    return false
                }
                placement = .before(beforeId)
            } else {
                placement = .end
            }
        }

        let newItemSection: String? = (sectionKey == listDetailUncategorizedKey) ? nil : sectionKey
        guard let sectionId = snap.sectionIdentifiers.first(where: {
            if case .section(let key) = $0 { return key == sectionKey }
            return false
        }) else {
            return false
        }

        var copy = item
        var changed = false

        if copy.section != newItemSection {
            copy.section = newItemSection
            changed = true
        }
        if copy.parentId != newParentId {
            copy.parentId = newParentId
            changed = true
        }

        let sectionRows = snap.itemIdentifiers(inSection: sectionId)
        var sectionItemIds: [UUID] = []
        for row in sectionRows {
            if case .item(let rid, _) = row, rid != itemId {
                sectionItemIds.append(rid)
            }
        }
        if sectionItemIds.isEmpty, !parent.prefs.sectionExpanded(sectionKey, in: parent.listId) {
            sectionItemIds = parent.store.items
                .filter { item in
                    item.listId == parent.listId
                        && item.deletedAt == nil
                        && item.parentId == nil
                        && ((item.section ?? listDetailUncategorizedKey) == sectionKey)
                        && item.id != itemId
                }
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(\.id)
        }

        let insertIdx: Int
        switch placement {
        case .end:
            insertIdx = sectionItemIds.count
        case .before(let targetId):
            insertIdx = sectionItemIds.firstIndex(of: targetId) ?? 0
        case .after(let targetId), .inside(let targetId):
            guard let targetIdxInSection = sectionItemIds.firstIndex(of: targetId) else { return false }
            var afterIdx = targetIdxInSection + 1
            while afterIdx < sectionItemIds.count,
                  let cand = parent.store.items.first(where: { $0.id == sectionItemIds[afterIdx] }),
                  isDescendant(cand.id, of: targetId) {
                afterIdx += 1
            }
            insertIdx = afterIdx
        }
        sectionItemIds.insert(itemId, at: insertIdx)

        var fullOrder: [UUID] = []
        for sec in snap.sectionIdentifiers {
            if case .section(let key) = sec, key == sectionKey {
                fullOrder.append(contentsOf: sectionItemIds)
            } else if case .section = sec {
                for row in snap.itemIdentifiers(inSection: sec) {
                    if case .item(let rid, _) = row, rid != itemId {
                        fullOrder.append(rid)
                    }
                }
            }
        }
        let currentFlatOrder = snap.sectionIdentifiers.flatMap { section -> [UUID] in
            guard case .section = section else { return [] }
            return snap.itemIdentifiers(inSection: section).compactMap { row in
                if case .item(let rid, _) = row { return rid }
                return nil
            }
        }
        let orderChanged = fullOrder != currentFlatOrder
        guard changed || orderChanged else { return false }

        let listId = parent.listId
        let store = parent.store
        let prefs = parent.prefs
        // Apply synchronously so the data source reflects the new state before
        // `coordinator.drop(_:toItemAt:)` animates the preview; otherwise UIKit
        // animates to a stale indexPath and the move visually snaps back.
        if changed {
            store.applyUpdateWithSubtreeCascadesSync(copy)
        }
        if prefs.sort(for: listId) != .manual {
            prefs.setSort(.manual, for: listId)
        }
        let expandedTargetSection = !prefs.sectionExpanded(sectionKey, in: listId)
        if expandedTargetSection {
            prefs.setSectionExpanded(true, sectionId: sectionKey, in: listId)
        }
        store.applyReorderItemsSync(in: listId, flatOrderedIds: fullOrder)
        applySnapshot(
            animated: false,
            reconfigure: expandedTargetSection ? [.sectionHeader(key: sectionKey)] : []
        )
        return true
    }

    @discardableResult
    func performSectionReorder(sourceKey: String,
                               to target: ListDetailCollectionView.SectionDropTarget?,
                               fallbackDestination dest: IndexPath?) -> Bool {
        guard let parent = parent, let list = parent.list else { return false }
        let snap = dataSource.snapshot()
        let namedKeys = list.sections
            .sorted { $0.position < $1.position }
            .map(\.id.uuidString)
        guard let oldIdx = namedKeys.firstIndex(of: sourceKey) else { return false }

        var rebuilt = namedKeys
        rebuilt.remove(at: oldIdx)

        if case .before(let destKey) = target,
           destKey == listDetailUncategorizedKey {
            rebuilt.append(sourceKey)
        } else if case .before(let destKey) = target,
                  destKey != sourceKey,
                  let targetIdx = namedKeys.firstIndex(of: destKey) {
            let adjusted = targetIdx > oldIdx ? targetIdx - 1 : targetIdx
            rebuilt.insert(sourceKey, at: max(0, min(adjusted, rebuilt.count)))
        } else if target == .afterLast {
            rebuilt.append(sourceKey)
        } else if let dest = dest,
                  isPastEnd(dest, in: snap) || isLastCellOfLastSection(dest, in: snap) {
            rebuilt.append(sourceKey)
        } else {
            return false
        }

        // No-op moves (same position): skip the store write and signal a
        // rejected drop so the preview animates back to its original cell.
        if rebuilt == namedKeys { return false }

        let orderedIds = rebuilt.compactMap { UUID(uuidString: $0) }
        let listId = parent.listId
        let store = parent.store
        // Apply synchronously so the data source reflects the new ordering
        // before `coordinator.drop(_:toItemAt:)` animates.
        store.applyReorderSectionsSync(in: listId, orderedIds: orderedIds)
        applySnapshot(animated: false)
        return true
    }

    private func isPastEnd(_ dest: IndexPath,
                           in snap: NSDiffableDataSourceSnapshot<
                            ListDetailCollectionView.SectionKey,
                            ListDetailCollectionView.RowItem
                           >) -> Bool {
        let lastSectionIdx = snap.sectionIdentifiers.count - 1
        guard lastSectionIdx >= 0 else { return false }
        if dest.section > lastSectionIdx { return true }
        if dest.section == lastSectionIdx {
            let count = snap.itemIdentifiers(inSection: snap.sectionIdentifiers[lastSectionIdx]).count
            return dest.item >= count
        }
        return false
    }

    private func isLastCellOfLastSection(_ dest: IndexPath,
                                         in snap: NSDiffableDataSourceSnapshot<
                                            ListDetailCollectionView.SectionKey,
                                            ListDetailCollectionView.RowItem
                                         >) -> Bool {
        let lastSectionIdx = snap.sectionIdentifiers.count - 1
        guard lastSectionIdx >= 0, dest.section == lastSectionIdx else { return false }
        let count = snap.itemIdentifiers(inSection: snap.sectionIdentifiers[lastSectionIdx]).count
        return count > 0 && dest.item == count - 1
    }
}
