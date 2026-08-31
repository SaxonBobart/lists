import UIKit

extension ListDetailCollectionView.Coordinator {
    private static let sectionDropVerticalPad: CGFloat = 8
    private static let sectionDropExitBottomPadding: CGFloat = 24

    struct SectionDropGeometry {
        let key: String
        let headerFrame: CGRect
    }

    // MARK: Drag

    func collectionView(_ collectionView: UICollectionView,
                        itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return [] }
        // Disable drag while the user is in select mode — the
        // row tap already does double duty as selection, and dragging
        // would steal taps and feel chaotic.
        if parent?.inSelectMode == true { return [] }
        if parent?.isDestinationModeActive == true { return [] }
        switch row {
        case .item(let id, let indent):
            let drag = UIDragItem(itemProvider: ItemMoveDragPayload.itemProvider(for: id))
            drag.localObject = row
            draggingItemId = id
            dragSourceHidden = false
            let grabLocation = session.location(in: collectionView)
            dragGrabX = grabLocation.x
            if let attributes = collectionView.collectionViewLayout
                .layoutAttributesForItem(at: indexPath) {
                dragGrabLocalX = grabLocation.x - attributes.frame.minX
            } else {
                dragGrabLocalX = nil
            }
            dragGrabDepth = indent
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
                self.hideColumnSectionDropCue()
                self.applySnapshot(animated: true)
            }
            self.draggingItemId = nil
            self.draggingRowHeight = nil
            self.dragSourceHidden = false
            self.dragGrabX = nil
            self.dragGrabLocalX = nil
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
        dragGrabLocalX = nil
        clearSectionDropTarget()
        clearItemDropTarget()
        if needsRestore {
            applySnapshot(animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
        if let draggingItemId,
           let edgeTarget = resolvedItemDropTargetForVerticalExit(
                collectionView: collectionView,
                touch: session.location(in: collectionView),
                sourceId: draggingItemId
           ) {
            clearSectionDropTarget()
            setItemDropTarget(edgeTarget, in: collectionView)
            return
        }
        if let draggingSectionKey,
           let edgeTarget = resolvedSectionDropTargetForVerticalExit(
                collectionView: collectionView,
                touch: session.location(in: collectionView),
                sourceKey: draggingSectionKey
           ) {
            clearItemDropTarget()
            setSectionDropTarget(edgeTarget)
            return
        }
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
        if parent?.presentation == .columns {
            updateColumnSectionDropCue(for: target)
            return
        }
        applySnapshot(animated: true)
    }

    private func clearSectionDropTarget() {
        guard sectionDropTarget != nil else { return }
        sectionDropTarget = nil
        if parent?.presentation == .columns {
            hideColumnSectionDropCue()
            return
        }
        applySnapshot(animated: true)
    }

    private func resolvedSectionDropTarget(collectionView: UICollectionView,
                                           session: UIDropSession,
                                           destination: IndexPath?,
                                           sourceKey: String) -> ListDetailCollectionView.SectionDropTarget? {
        resolvedSectionDropTarget(
            collectionView: collectionView,
            touch: session.location(in: collectionView),
            destination: destination,
            sourceKey: sourceKey
        )
    }

    private func resolvedSectionDropTarget(collectionView: UICollectionView,
                                           touch location: CGPoint,
                                           destination: IndexPath?,
                                           sourceKey: String) -> ListDetailCollectionView.SectionDropTarget? {
        let snap = dataSource.snapshot()

        if let currentTarget = sectionDropTarget,
           let placeholderPath = dataSource.indexPath(
                for: .sectionDropPlaceholder(id: Self.sectionDropPlaceholderId)
           ),
           let placeholderAttributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: placeholderPath),
           placeholderAttributes.frame.insetBy(dx: 0, dy: -12).contains(location) {
            return currentTarget
        }

        var sections: [SectionDropGeometry] = []
        for sectionId in snap.sectionIdentifiers {
            guard case .section(let key) = sectionId,
                  key != sourceKey,
                  let indexPath = dataSource.indexPath(for: .sectionHeader(key: key)),
                  let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
                continue
            }
            sections.append(SectionDropGeometry(key: key, headerFrame: attributes.frame))
        }

        let namedKeys = parent?.list?.sections
            .sorted { $0.position < $1.position }
            .map(\.id.uuidString) ?? []
        let hasOthers = snap.sectionIdentifiers.contains {
            if case .section(let key) = $0 { return key == listDetailUncategorizedKey }
            return false
        }

        if parent?.presentation == .columns {
            return resolvedColumnSectionDropTarget(
                sections: sections,
                touch: location,
                sourceKey: sourceKey,
                namedSectionKeys: namedKeys,
                hasUncategorizedSection: hasOthers
            )
        }

        guard let last = lastIndexPath(in: snap),
              let lastAttributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: last) else {
            return nil
        }

        return resolvedSectionDropTarget(
            sections: sections,
            touch: location,
            sourceKey: sourceKey,
            namedSectionKeys: namedKeys,
            hasUncategorizedSection: hasOthers,
            lastContentMaxY: lastAttributes.frame.maxY,
            fallbackBottomY: sectionDropFallbackBottomY(collectionView)
        )
    }

    func resolvedSectionDropTarget(
        sections: [SectionDropGeometry],
        touch location: CGPoint,
        sourceKey: String,
        namedSectionKeys: [String],
        hasUncategorizedSection: Bool,
        lastContentMaxY: CGFloat,
        fallbackBottomY: CGFloat
    ) -> ListDetailCollectionView.SectionDropTarget? {
        guard sections.isEmpty == false else { return nil }

        if let first = sections.first,
           location.y < first.headerFrame.maxY - Self.sectionDropVerticalPad {
            let target: ListDetailCollectionView.SectionDropTarget = .before(first.key)
            return isNoOpSectionDrop(target, sourceKey: sourceKey, namedKeys: namedSectionKeys) ? nil : target
        }

        for section in sections {
            let headerBand = section.headerFrame.insetBy(dx: 0, dy: -Self.sectionDropVerticalPad)
            if headerBand.contains(location) {
                let target: ListDetailCollectionView.SectionDropTarget = .before(section.key)
                return isNoOpSectionDrop(target, sourceKey: sourceKey, namedKeys: namedSectionKeys) ? nil : target
            }
        }

        if location.y >= lastContentMaxY - Self.sectionDropVerticalPad
            || location.y >= fallbackBottomY - Self.sectionDropExitBottomPadding {
            let target = endSectionDropTarget(
                hasUncategorizedSection: hasUncategorizedSection
            )
            return isNoOpSectionDrop(target, sourceKey: sourceKey, namedKeys: namedSectionKeys) ? nil : target
        }

        return nil
    }

    func resolvedColumnSectionDropTarget(
        sections: [SectionDropGeometry],
        touch location: CGPoint,
        sourceKey: String,
        namedSectionKeys: [String],
        hasUncategorizedSection: Bool
    ) -> ListDetailCollectionView.SectionDropTarget? {
        let ordered = sections.sorted { $0.headerFrame.minX < $1.headerFrame.minX }
        guard !ordered.isEmpty else { return nil }

        for section in ordered where location.x < section.headerFrame.midX {
            let target: ListDetailCollectionView.SectionDropTarget = .before(section.key)
            return isNoOpSectionDrop(
                target,
                sourceKey: sourceKey,
                namedKeys: namedSectionKeys
            ) ? nil : target
        }

        let target = endSectionDropTarget(
            hasUncategorizedSection: hasUncategorizedSection
        )
        return isNoOpSectionDrop(
            target,
            sourceKey: sourceKey,
            namedKeys: namedSectionKeys
        ) ? nil : target
    }

    private func resolvedSectionDropTargetForVerticalExit(
        collectionView: UICollectionView,
        touch: CGPoint,
        sourceKey: String
    ) -> ListDetailCollectionView.SectionDropTarget? {
        let pinnedY: CGFloat
        if touch.y < collectionView.bounds.minY {
            pinnedY = -Self.sectionDropVerticalPad
        } else if touch.y > collectionView.bounds.maxY {
            pinnedY = sectionDropFallbackBottomY(collectionView)
        } else {
            return nil
        }
        return resolvedSectionDropTarget(
            collectionView: collectionView,
            touch: CGPoint(x: touch.x, y: pinnedY),
            destination: nil,
            sourceKey: sourceKey
        )
    }

    private func sectionDropFallbackBottomY(_ collectionView: UICollectionView) -> CGFloat {
        max(collectionView.contentSize.height, collectionView.bounds.maxY)
            + draggingSectionHeight
            + Self.sectionDropExitBottomPadding
    }

    private func endSectionDropTarget(sourceKey: String) -> ListDetailCollectionView.SectionDropTarget? {
        let snap = dataSource.snapshot()
        let hasOthers = snap.sectionIdentifiers.contains {
            if case .section(let key) = $0 { return key == listDetailUncategorizedKey }
            return false
        }
        let target = endSectionDropTarget(hasUncategorizedSection: hasOthers)
        return isNoOpSectionDrop(target, sourceKey: sourceKey) ? nil : target
    }

    private func endSectionDropTarget(
        hasUncategorizedSection: Bool
    ) -> ListDetailCollectionView.SectionDropTarget {
        hasUncategorizedSection ? .before(listDetailUncategorizedKey) : .afterLast
    }

    private func isNoOpSectionDrop(_ target: ListDetailCollectionView.SectionDropTarget, sourceKey: String) -> Bool {
        guard let parent = parent, let list = parent.list else { return true }
        let namedKeys = list.sections
            .sorted { $0.position < $1.position }
            .map(\.id.uuidString)
        return isNoOpSectionDrop(target, sourceKey: sourceKey, namedKeys: namedKeys)
    }

    private func isNoOpSectionDrop(
        _ target: ListDetailCollectionView.SectionDropTarget,
        sourceKey: String,
        namedKeys: [String]
    ) -> Bool {
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
        hideColumnSectionDropCue()
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

    private func updateColumnSectionDropCue(
        for target: ListDetailCollectionView.SectionDropTarget?
    ) {
        guard let target,
              let collectionView,
              let layout = collectionView.collectionViewLayout as? ListDetailColumnsLayout else {
            hideColumnSectionDropCue()
            return
        }
        collectionView.layoutIfNeeded()

        let snapshot = dataSource.snapshot()
        let targetSectionIndex: Int?
        let cueX: CGFloat?
        switch target {
        case .before(let key):
            targetSectionIndex = snapshot.sectionIdentifiers.firstIndex(of: .section(key: key))
            cueX = targetSectionIndex
                .flatMap(layout.columnFrame(forSection:))
                .map { $0.minX - 6 }
        case .afterLast:
            targetSectionIndex = snapshot.sectionIdentifiers.indices.reversed().first {
                if case .section = snapshot.sectionIdentifiers[$0] { return true }
                return false
            }
            cueX = targetSectionIndex
                .flatMap(layout.columnFrame(forSection:))
                .map { $0.maxX + 6 }
        }
        guard let targetSectionIndex,
              let columnFrame = layout.columnFrame(forSection: targetSectionIndex),
              let cueX else {
            hideColumnSectionDropCue()
            return
        }

        let cue: UIView
        if let sectionDropCueView {
            cue = sectionDropCueView
        } else {
            let view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            view.backgroundColor = UIColor(parent?.listColor ?? .accentColor)
            view.layer.cornerRadius = 2
            view.accessibilityIdentifier = "list.columns.section.drop.cue"
            collectionView.addSubview(view)
            sectionDropCueView = view
            cue = view
        }
        UIView.performWithoutAnimation {
            cue.frame = CGRect(
                x: cueX - 2,
                y: columnFrame.minY + 8,
                width: 4,
                height: max(44, columnFrame.height - 16)
            )
            cue.isHidden = false
            collectionView.bringSubviewToFront(cue)
        }
    }

    private func hideColumnSectionDropCue() {
        sectionDropCueView?.removeFromSuperview()
        sectionDropCueView = nil
    }
}
