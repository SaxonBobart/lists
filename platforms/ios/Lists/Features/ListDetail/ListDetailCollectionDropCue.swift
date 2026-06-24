import UIKit

extension ListDetailCollectionView.Coordinator {
    func setItemDropTarget(_ target: ListDetailCollectionView.ItemDropTarget?,
                           in collectionView: UICollectionView) {
        itemDropTarget = target
        updateItemDropCue(for: target, in: collectionView)
    }

    func clearItemDropTarget() {
        itemDropTarget = nil
        hideItemDropCue()
        clearItemDropTransforms()
    }

    private static func indentLevelColor(for depth: Int) -> UIColor {
        if depth >= 8 { return .systemGray }
        switch depth {
        case 1: return .systemGreen
        case 2: return .systemYellow
        case 3: return .systemOrange
        case 4: return .systemRed
        case 5: return .systemPink
        case 6: return .systemPurple
        case 7: return .systemBlue
        default: return .systemCyan
        }
    }

    private func updateItemDropCue(for target: ListDetailCollectionView.ItemDropTarget?,
                                   in collectionView: UICollectionView) {
        guard let target, let parent else {
            hideItemDropCue()
            clearItemDropTransforms()
            return
        }

        collectionView.layoutIfNeeded()
        clearItemDropTransforms()

        let color = UIColor(parent.listColor)
        switch target {
        case .nestInto(let targetId):
            guard let frame = frameForItem(targetId, in: collectionView) else {
                hideItemDropCue()
                return
            }
            showItemDropCue(
                frame: frame.insetBy(dx: 8, dy: 2),
                color: color,
                style: .nesting,
                in: collectionView
            )
        case .gap(let gap):
            guard let gy = gapY(for: gap, in: collectionView) else {
                hideItemDropCue()
                return
            }
            let leading = ListDetailLayout.leadingEdge
                + CGFloat(gap.indent) * ListDetailLayout.indentStep
            let space = draggingRowHeight ?? Self.itemDropCueSpace
            let barWidth: CGFloat = 3
            let inset: CGFloat = 3
            let frame = CGRect(
                x: leading,
                y: gy + inset,
                width: barWidth,
                height: max(0, space - inset * 2)
            )
            applyItemDropTransforms(after: gy, in: collectionView)
            showItemDropCue(
                frame: frame,
                color: Self.indentLevelColor(for: gap.indent),
                style: .placement,
                in: collectionView
            )
        }
    }

    private func showItemDropCue(frame: CGRect,
                                 color: UIColor,
                                 style: ListDetailCollectionView.ItemDropCueStyle,
                                 in collectionView: UICollectionView) {
        let cue: UIView
        if let existing = itemDropCueView {
            cue = existing
        } else {
            let view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            view.accessibilityIdentifier = "item.drop.cue"
            view.layer.masksToBounds = true
            collectionView.addSubview(view)
            itemDropCueView = view
            cue = view
        }

        if style == .nesting {
            cue.layer.cornerRadius = 8
            cue.backgroundColor = color.withAlphaComponent(0.16)
            cue.layer.borderColor = color.withAlphaComponent(0.35).cgColor
            cue.layer.borderWidth = 0
        } else {
            cue.layer.cornerRadius = frame.width / 2
            cue.backgroundColor = color.withAlphaComponent(0.85)
            cue.layer.borderColor = UIColor.clear.cgColor
            cue.layer.borderWidth = 0
        }
        UIView.performWithoutAnimation {
            cue.frame = frame
            cue.isHidden = false
            cue.alpha = 1
            collectionView.bringSubviewToFront(cue)
        }
    }

    private func hideItemDropCue() {
        itemDropCueView?.removeFromSuperview()
        itemDropCueView = nil
    }

    private func applyItemDropTransforms(after gapY: CGFloat, in collectionView: UICollectionView) {
        let shift = draggingRowHeight ?? Self.itemDropCueSpace
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath),
                  attributes.frame.minY >= gapY - 0.5,
                  !isDraggingSourceCell(at: indexPath) else {
                continue
            }
            cell.transform = CGAffineTransform(translationX: 0, y: shift)
            itemDropShiftedCells.append(cell)
        }
    }

    private func clearItemDropTransforms() {
        for cell in itemDropShiftedCells {
            cell.transform = .identity
        }
        itemDropShiftedCells.removeAll()
    }

    private func isDraggingSourceCell(at indexPath: IndexPath) -> Bool {
        guard let draggingItemId,
              let row = dataSource.itemIdentifier(for: indexPath),
              case .item(let id, _) = row else {
            return false
        }
        return id == draggingItemId
    }

    private func gapY(for gap: ListDetailCollectionView.GapPosition,
                      in collectionView: UICollectionView) -> CGFloat? {
        if let beforeId = gap.beforeRowId {
            return frameForItem(beforeId, in: collectionView)?.minY
        }
        if let lastFrame = lastItemFrame(inSection: gap.sectionKey, in: collectionView) {
            return lastFrame.maxY
        }
        if let headerFrame = frameForSectionHeader(gap.sectionKey, in: collectionView) {
            return headerFrame.maxY
        }
        return sectionFallbackY(gap.sectionKey, in: collectionView)
    }

    private func frameForItem(_ id: UUID, in collectionView: UICollectionView) -> CGRect? {
        for row in dataSource.snapshot().itemIdentifiers {
            guard case .item(let rowId, let indent) = row,
                  rowId == id,
                  let indexPath = dataSource.indexPath(for: .item(id: rowId, indent: indent)) else {
                continue
            }
            return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
        }
        return nil
    }

    private func frameForSectionHeader(_ key: String, in collectionView: UICollectionView) -> CGRect? {
        let row = ListDetailCollectionView.RowItem.sectionHeader(key: key)
        guard let indexPath = dataSource.indexPath(for: row) else { return nil }
        return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
    }

    private func lastItemFrame(inSection key: String, in collectionView: UICollectionView) -> CGRect? {
        itemFrames(inSection: key, in: collectionView).last
    }

    private func itemFrames(inSection key: String, in collectionView: UICollectionView) -> [CGRect] {
        let sectionId = ListDetailCollectionView.SectionKey.section(key: key)
        let sourceId = draggingItemId
        return dataSource.snapshot()
            .itemIdentifiers(inSection: sectionId)
            .compactMap { row -> CGRect? in
                guard case .item(let id, let indent) = row,
                      id != sourceId,
                      !(sourceId.map { isDescendant(id, of: $0) } ?? false),
                      let indexPath = dataSource.indexPath(for: .item(id: id, indent: indent)) else {
                    return nil
                }
                return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
            }
            .sorted { $0.minY < $1.minY }
    }

    private func sectionFallbackY(_ key: String, in collectionView: UICollectionView) -> CGFloat? {
        let snap = dataSource.snapshot()
        guard let sectionIndex = snap.sectionIdentifiers.firstIndex(of: .section(key: key)) else { return nil }
        if sectionIndex == 0 { return 0 }
        let previousSection = snap.sectionIdentifiers[sectionIndex - 1]
        return snap.itemIdentifiers(inSection: previousSection)
            .compactMap { row -> CGRect? in
                guard let indexPath = dataSource.indexPath(for: row) else { return nil }
                return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
            }
            .map(\.maxY)
            .max()
    }
}
