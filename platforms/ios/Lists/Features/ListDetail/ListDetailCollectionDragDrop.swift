import UIKit

extension ListDetailCollectionView.Coordinator {
    // MARK: Drag

    func collectionView(_ collectionView: UICollectionView,
                        itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return [] }
        // Disable drag while the user is in select mode — the
        // row tap already does double duty as selection, and dragging
        // would steal taps and feel chaotic.
        if parent?.inSelectMode == true { return [] }
        if parent?.moveSession.isActive == true { return [] }
        switch row {
        case .item(let id, let indent):
            let drag = UIDragItem(itemProvider: ItemMoveDragPayload.itemProvider(for: id))
            drag.localObject = row
            draggingItemId = id
            dragSourceHidden = false
            dragGrabX = session.location(in: collectionView).x
            dragGrabDepth = indent
            if let item = parent?.store.item(id) {
                parent?.onMoveShelfDragCandidateChanged(item)
            }
            // The dragged row is deleted from the list once the drag moves
            // (see computeDropProposal), which also kills UIKit's default
            // cell-backed preview. So give UIKit a cell-INDEPENDENT preview
            // rendered to an image. `drawHierarchy(afterScreenUpdates:true)`
            // is the one snapshot path that captures SwiftUI-hosted content
            // — `snapshotView`/`layer.render` come back black.
            if let cell = collectionView.cellForItem(at: indexPath) {
                draggingRowHeight = cell.bounds.height
                let image = UIGraphicsImageRenderer(bounds: cell.bounds).image { _ in
                    cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
                }
                let preview = UIImageView(image: image)
                preview.frame = CGRect(origin: .zero, size: cell.bounds.size)
                drag.previewProvider = {
                    let params = UIDragPreviewParameters()
                    params.backgroundColor = .clear
                    return UIDragPreview(view: preview, parameters: params)
                }
            }
            clearItemDropTarget()
            // NOTE: the dragged subtree is removed from the list lazily,
            // on the first drop-session update (see computeDropProposal) —
            // i.e. only once the item is actually being moved. These rows
            // share their long-press with a context menu; removing the row
            // on the bare lift blanked it out whenever the menu opened.
            return [drag]
        case .sectionHeader(let key) where key != listDetailUncategorizedKey:
            let drag = UIDragItem(itemProvider: NSItemProvider())
            drag.localObject = row
            clearItemDropTarget()
            draggingSectionHeight = collectionView.cellForItem(at: indexPath)?.bounds.height ?? 44
            sectionDropTarget = nil
            // Collapse this section's items so the floating preview
            // travels alone. Re-apply on the next runloop so the cell
            // snapshot used as the drag preview is captured first.
            DispatchQueue.main.async { [weak self] in
                self?.draggingSectionKey = key
                self?.applySnapshot(animated: true)
            }
            return [drag]
        default:
            return []
        }
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        // Dispatch async so the clear runs AFTER `itemsForBeginning`'s
        // async block — otherwise a quick-release before the lift-state
        // is applied could leave the section permanently collapsed.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Restore the dragged subtree only if it was actually hidden
            // and the drag was cancelled (a committed drop clears
            // draggingItemId in performDropWith first and rebuilds via the
            // store update).
            let needsRestore = self.draggingItemId != nil && self.dragSourceHidden
            if self.draggingSectionKey != nil || self.sectionDropTarget != nil {
                self.draggingSectionKey = nil
                self.sectionDropTarget = nil
                self.applySnapshot(animated: true)
            }
            self.draggingItemId = nil
            self.draggingRowHeight = nil
            self.dragSourceHidden = false
            self.dragGrabX = nil
            self.parent?.onMoveShelfDragCandidateChanged(nil)
            self.clearItemDropTarget()
            if needsRestore {
                self.applySnapshot(animated: true)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
        // Restore the dragged row if it was hidden and the drop was cancelled
        // (performDropWith clears draggingItemId before this fires on a
        // successful drop, so needsRestore is false in that path).
        let needsRestore = draggingItemId != nil && dragSourceHidden
        draggingItemId = nil
        draggingRowHeight = nil
        dragSourceHidden = false
        dragGrabX = nil
        parent?.onMoveShelfDragCandidateChanged(nil)
        clearSectionDropTarget()
        clearItemDropTarget()
        if needsRestore {
            applySnapshot(animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
        clearSectionDropTarget()
        clearItemDropTarget()
    }

    // MARK: Drop validation

    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        false
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        false
    }

    func collectionView(_ collectionView: UICollectionView,
                        dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destination: IndexPath?) -> UICollectionViewDropProposal {
        computeDropProposal(collectionView: collectionView, session: session, destination: destination)
    }

    private func setSectionDropTarget(_ target: ListDetailCollectionView.SectionDropTarget?) {
        guard sectionDropTarget != target else { return }
        sectionDropTarget = target
        applySnapshot(animated: true)
    }

    private func clearSectionDropTarget() {
        guard sectionDropTarget != nil else { return }
        sectionDropTarget = nil
        applySnapshot(animated: true)
    }

    private func resolvedSectionDropTarget(collectionView: UICollectionView,
                                           session: UIDropSession,
                                           destination: IndexPath?,
                                           sourceKey: String) -> ListDetailCollectionView.SectionDropTarget? {
        let location = session.location(in: collectionView)
        let snap = dataSource.snapshot()

        if let currentTarget = sectionDropTarget,
           let placeholderPath = dataSource.indexPath(
                for: .sectionDropPlaceholder(id: Self.sectionDropPlaceholderId)
           ),
           let placeholderAttributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: placeholderPath),
           placeholderAttributes.frame.insetBy(dx: 0, dy: -12).contains(location) {
            return currentTarget
        }

        for sectionId in snap.sectionIdentifiers {
            guard case .section(let key) = sectionId,
                  key != sourceKey,
                  let indexPath = dataSource.indexPath(for: .sectionHeader(key: key)),
                  let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
                continue
            }
            let headerBand = attributes.frame.insetBy(dx: 0, dy: -8)
            if headerBand.contains(location) {
                let target: ListDetailCollectionView.SectionDropTarget = .before(key)
                return isNoOpSectionDrop(target, sourceKey: sourceKey) ? nil : target
            }
        }

        guard let last = lastIndexPath(in: snap),
              let lastAttributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: last) else {
            return nil
        }
        let bottomBand = CGRect(
            x: 0,
            y: lastAttributes.frame.maxY - 8,
            width: max(collectionView.bounds.width, collectionView.contentSize.width),
            height: 80
        )
        if bottomBand.contains(location) {
            return endSectionDropTarget(sourceKey: sourceKey)
        }

        if destination == nil, location.y > lastAttributes.frame.maxY {
            return endSectionDropTarget(sourceKey: sourceKey)
        }

        return nil
    }

    private func endSectionDropTarget(sourceKey: String) -> ListDetailCollectionView.SectionDropTarget? {
        let snap = dataSource.snapshot()
        let hasOthers = snap.sectionIdentifiers.contains {
            if case .section(let key) = $0 { return key == listDetailUncategorizedKey }
            return false
        }
        let target: ListDetailCollectionView.SectionDropTarget = hasOthers ? .before(listDetailUncategorizedKey) : .afterLast
        return isNoOpSectionDrop(target, sourceKey: sourceKey) ? nil : target
    }

    private func isNoOpSectionDrop(_ target: ListDetailCollectionView.SectionDropTarget, sourceKey: String) -> Bool {
        guard let parent = parent, let list = parent.list else { return true }
        let namedKeys = list.sections
            .sorted { $0.position < $1.position }
            .map(\.id.uuidString)
        guard let oldIdx = namedKeys.firstIndex(of: sourceKey) else { return true }

        switch target {
        case .before(let key) where key == sourceKey:
            return true
        case .before(let key) where key == listDetailUncategorizedKey:
            return oldIdx == namedKeys.count - 1
        case .before(let key):
            guard let targetIdx = namedKeys.firstIndex(of: key) else { return true }
            let adjusted = targetIdx > oldIdx ? targetIdx - 1 : targetIdx
            return adjusted == oldIdx
        case .afterLast:
            return oldIdx == namedKeys.count - 1
        }
    }

    /// Remove the dragged subtree from the list the first time the drag
    /// actually moves, so its space closes up. Done once per drag; the
    /// lift preview is already committed by now, so the floating preview
    /// isn't orphaned.
    private func hideDraggedSourceIfNeeded() {
        guard draggingItemId != nil, !dragSourceHidden else { return }
        dragSourceHidden = true
        applySnapshot(animated: true)
    }

    private func computeDropProposal(collectionView: UICollectionView, session: UIDropSession, destination: IndexPath?) -> UICollectionViewDropProposal {
        guard let dragItem = session.localDragSession?.items.first,
              let sourceRow = dragItem.localObject as? ListDetailCollectionView.RowItem else {
            return UICollectionViewDropProposal(operation: .cancel)
        }

        if case .item(let id, _) = sourceRow {
            let target = resolvedItemDropTarget(collectionView: collectionView, session: session, sourceId: id)
            setItemDropTarget(target, in: collectionView)
            // Now that the item is genuinely being dragged (not just lifted
            // for the context menu), collapse its row out of the list.
            hideDraggedSourceIfNeeded()
            if target == nil {
                return UICollectionViewDropProposal(operation: .forbidden)
            }
            return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
        }

        guard let dest = destination else {
            if case .sectionHeader(let sourceKey) = sourceRow {
                let target = resolvedSectionDropTarget(
                    collectionView: collectionView,
                    session: session,
                    destination: nil,
                    sourceKey: sourceKey
                )
                setSectionDropTarget(target)
                return target == nil
                    ? UICollectionViewDropProposal(operation: .forbidden)
                    : UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            }
            clearItemDropTarget()
            return UICollectionViewDropProposal(operation: .cancel)
        }

        let snapshot = dataSource.snapshot()
        guard dest.section < snapshot.sectionIdentifiers.count else {
            if case .sectionHeader(let sourceKey) = sourceRow {
                let target = resolvedSectionDropTarget(
                    collectionView: collectionView,
                    session: session,
                    destination: destination,
                    sourceKey: sourceKey
                )
                setSectionDropTarget(target)
                return target == nil
                    ? UICollectionViewDropProposal(operation: .forbidden)
                    : UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            }
            clearItemDropTarget()
            return UICollectionViewDropProposal(operation: .cancel)
        }

        switch sourceRow {
        case .sectionHeader(let sourceKey):
            clearItemDropTarget()
            let target = resolvedSectionDropTarget(
                collectionView: collectionView,
                session: session,
                destination: destination,
                sourceKey: sourceKey
            )
            setSectionDropTarget(target)
            if target != nil {
                return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            }

            let destRow = dataSource.itemIdentifier(for: dest)

            // Source-on-self / source-section-own-area: return `.move`
            // with `.unspecified` (not `.forbidden`) because UIKit fires
            // a final dropSessionDidUpdate at release time that often
            // reports the source indexPath. `.forbidden` there makes
            // UIKit skip performDropWith entirely and reject every drop.
            // `.unspecified` shows no insertion line and
            // `performSectionReorder` gracefully no-ops on same-position.
            if case .sectionHeader(let destKey) = destRow, destKey == sourceKey {
                return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            }
            if destRow == nil,
               dest.section < snapshot.sectionIdentifiers.count,
               case .section(let destKey) = snapshot.sectionIdentifiers[dest.section],
               destKey == sourceKey {
                return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            }

            // Everything that is not a real section boundary is invalid
            // for section reordering. That includes item rows inside a
            // section and the Sub-Lists area.
            return UICollectionViewDropProposal(operation: .forbidden)

        default:
            return UICollectionViewDropProposal(operation: .cancel)
        }
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first,
              let sourceRow = item.dragItem.localObject as? ListDetailCollectionView.RowItem else { return }

        // Clear the drag-collapse flag now so the next snapshot rebuild
        // (triggered by the async store update) re-emits the section's
        // items.
        let pendingSectionDropTarget = sectionDropTarget
        let pendingItemDropTarget = itemDropTarget
        draggingSectionKey = nil
        draggingItemId = nil
        dragSourceHidden = false
        sectionDropTarget = nil
        clearItemDropTarget()

        let destination = coordinator.destinationIndexPath
        switch sourceRow {
        case .item(let id, _):
            if let pendingItemDropTarget {
                _ = performItemReorder(itemId: id, dropTarget: pendingItemDropTarget)
            }
            let finalTarget: IndexPath = currentIndexPath(forItemId: id)
                ?? destination
                ?? IndexPath(item: 0, section: 0)
            coordinator.drop(item.dragItem, toItemAt: finalTarget)
        case .sectionHeader(let key):
            _ = performSectionReorder(sourceKey: key, to: pendingSectionDropTarget, fallbackDestination: destination)
            // Animate the preview to the section header's CURRENT
            // indexPath after the (possibly applied) reorder. When the
            // finger landed in another section's items area, this avoids
            // a transient mid-state where UIKit slots the section preview
            // between that section's header and its first item.
            let finalTarget: IndexPath = dataSource.indexPath(for: .sectionHeader(key: key))
                ?? destination
                ?? lastIndexPath(in: dataSource.snapshot())
                ?? IndexPath(item: 0, section: 0)
            coordinator.drop(item.dragItem, toItemAt: finalTarget)
        default:
            return
        }
    }

    private func lastIndexPath(in snap: NSDiffableDataSourceSnapshot<ListDetailCollectionView.SectionKey, ListDetailCollectionView.RowItem>) -> IndexPath? {
        let lastSec = snap.sectionIdentifiers.count - 1
        guard lastSec >= 0 else { return nil }
        let count = snap.itemIdentifiers(inSection: snap.sectionIdentifiers[lastSec]).count
        guard count > 0 else { return nil }
        return IndexPath(item: count - 1, section: lastSec)
    }
}
