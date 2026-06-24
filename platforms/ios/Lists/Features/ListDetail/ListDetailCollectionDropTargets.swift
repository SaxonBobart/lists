import UIKit

extension ListDetailCollectionView.Coordinator {
    func resolvedItemDropTarget(collectionView: UICollectionView,
                                session: UIDropSession,
                                sourceId: UUID) -> ListDetailCollectionView.ItemDropTarget? {
        resolvedItemDropTarget(collectionView: collectionView,
                               touch: session.location(in: collectionView),
                               sourceId: sourceId)
    }

    /// Touch-based core, shared by the live drag session and the
    /// FAB-drag inline-create path (which has no `UIDropSession`).
    func resolvedItemDropTarget(collectionView: UICollectionView,
                                touch: CGPoint,
                                sourceId: UUID) -> ListDetailCollectionView.ItemDropTarget? {
        let snap = dataSource.snapshot()
        let sourceSubtreeDepth = subtreeDepthOf(sourceId)

        // Build per-section visible rows + header frames.
        struct SectionLayout {
            let key: String
            var headerFrame: CGRect?
            var rows: [ListDetailCollectionView.VisibleRow] = []
        }
        var sections: [SectionLayout] = []

        for sectionId in snap.sectionIdentifiers {
            guard case .section(let key) = sectionId else { continue }
            var layout = SectionLayout(key: key)
            for row in snap.itemIdentifiers(inSection: sectionId) {
                guard let indexPath = dataSource.indexPath(for: row),
                      let attrs = collectionView.collectionViewLayout
                          .layoutAttributesForItem(at: indexPath) else {
                    continue
                }
                switch row {
                case .sectionHeader:
                    layout.headerFrame = attrs.frame
                case .item(let id, let indent)
                    where id != sourceId && !isDescendant(id, of: sourceId):
                    layout.rows.append(ListDetailCollectionView.VisibleRow(id: id, depth: indent, frame: attrs.frame))
                default:
                    break
                }
            }
            layout.rows.sort { $0.frame.minY < $1.frame.minY }
            sections.append(layout)
        }

        // 1. Touch INSIDE a row's frame.
        //    Top half  -> gap above; bottom half -> gap below.
        //    Horizontal position drives indent throughout -- no separate nesting zone.
        for section in sections {
            for (i, row) in section.rows.enumerated() {
                guard row.frame.insetBy(dx: 0, dy: -2).contains(touch) else { continue }
                let relY = (touch.y - row.frame.minY) / max(row.frame.height, 1)
                if relY < 0.5 {
                    let above = i > 0 ? section.rows[i - 1] : nil
                    let indent = chooseIndent(touchX: touch.x,
                                              rowAboveDepth: above?.depth,
                                              rowBelowDepth: row.depth,
                                              sourceSubtreeDepth: sourceSubtreeDepth)
                    return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                      beforeRowId: row.id,
                                                                      indent: indent))
                }
                let below = i + 1 < section.rows.count ? section.rows[i + 1] : nil
                let indent = chooseIndent(touchX: touch.x,
                                          rowAboveDepth: row.depth,
                                          rowBelowDepth: below?.depth,
                                          sourceSubtreeDepth: sourceSubtreeDepth)
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                  beforeRowId: below?.id,
                                                                  indent: indent))
            }
        }

        // 2. Touch on a section header.
        for (idx, section) in sections.enumerated() {
            guard let headerFrame = section.headerFrame,
                  headerFrame.contains(touch) else { continue }
            let relY = (touch.y - headerFrame.minY) / max(headerFrame.height, 1)
            if relY < 0.45, idx > 0 {
                let prev = sections[idx - 1]
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: prev.key,
                                                                  beforeRowId: nil,
                                                                  indent: 0))
            }
            return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                              beforeRowId: section.rows.first?.id,
                                                              indent: 0))
        }

        // 3. Touch in a gap between rows / below last row of section.
        for (idx, section) in sections.enumerated() {
            guard let headerFrame = section.headerFrame else { continue }
            let nextHeaderMinY: CGFloat = {
                for after in sections.dropFirst(idx + 1) {
                    if let f = after.headerFrame { return f.minY }
                }
                // Add slack for the removed dragged row so you can still
                // position below the last visible item.
                return collectionView.contentSize.height
                    + (draggingRowHeight ?? Self.itemDropCueSpace)
            }()
            guard touch.y >= headerFrame.maxY, touch.y < nextHeaderMinY else { continue }

            if section.rows.isEmpty {
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                  beforeRowId: nil,
                                                                  indent: 0))
            }

            // Gap above first row.
            if touch.y < section.rows[0].frame.minY {
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                  beforeRowId: section.rows[0].id,
                                                                  indent: 0))
            }

            // Gaps between rows / after last row.
            for i in section.rows.indices {
                let current = section.rows[i]
                let below = i + 1 < section.rows.count ? section.rows[i + 1] : nil
                let upper = below?.frame.minY ?? nextHeaderMinY
                guard touch.y > current.frame.maxY, touch.y < upper else { continue }
                let indent = chooseIndent(touchX: touch.x,
                                          rowAboveDepth: current.depth,
                                          rowBelowDepth: below?.depth,
                                          sourceSubtreeDepth: sourceSubtreeDepth)
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                  beforeRowId: below?.id,
                                                                  indent: indent))
            }
        }

        return nil
    }

    /// Maps a horizontal touch position to a target indent.
    ///
    /// For a row drag, the indent is the lifted row's depth plus one level
    /// per `indentStep` of horizontal travel from the grab point -- relative
    /// motion, so it works the same wherever on the row the finger grabbed.
    /// A FAB drag has no grab origin and falls back to the absolute mapping
    /// (one level per step from the leading content edge). Either way the
    /// chosen depth is clamped by:
    /// - `rowAbove.depth + 1` -- cannot be deeper than one child of the row above.
    /// - `2 - sourceSubtreeDepth` -- keeps dragged descendants within the cap.
    /// - `rowBelow.depth` from below -- avoids splitting the next row's siblings.
    private func chooseIndent(touchX: CGFloat,
                              rowAboveDepth: Int?,
                              rowBelowDepth: Int?,
                              sourceSubtreeDepth: Int) -> Int {
        guard let rowAboveDepth = rowAboveDepth else { return 0 }
        let raw: Int
        if let grabX = dragGrabX {
            raw = dragGrabDepth + Int(((touchX - grabX) / ListDetailLayout.indentStep).rounded())
        } else {
            raw = Int(floor((touchX - ListDetailLayout.leadingEdge) / ListDetailLayout.indentStep))
        }
        let maxByAbove = rowAboveDepth + 1
        let maxIndent = min(maxByAbove, ListsNesting.maxDisplayDepth)
        let minIndent = max(0, min(rowBelowDepth ?? 0, maxIndent))
        return max(minIndent, min(raw, maxIndent))
    }
}
