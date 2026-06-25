import UIKit

extension ListDetailCollectionView.Coordinator {
    private static let itemDropVerticalPad: CGFloat = 12
    private static let itemDropBottomPadding: CGFloat = 18

    struct ItemDropSectionGeometry {
        let key: String
        let headerFrame: CGRect
        let rows: [ListDetailCollectionView.VisibleRow]
    }

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
        // Build per-section visible rows + header frames.
        var sections: [ItemDropSectionGeometry] = []

        for sectionId in snap.sectionIdentifiers {
            guard case .section(let key) = sectionId else { continue }
            var sectionRows: [ListDetailCollectionView.VisibleRow] = []
            var headerFrame: CGRect?
            for row in snap.itemIdentifiers(inSection: sectionId) {
                guard let indexPath = dataSource.indexPath(for: row),
                      let attrs = collectionView.collectionViewLayout
                          .layoutAttributesForItem(at: indexPath) else {
                    continue
                }
                switch row {
                case .sectionHeader:
                    headerFrame = attrs.frame
                case .item(let id, let indent)
                    where id != sourceId && !isDescendant(id, of: sourceId):
                    sectionRows.append(ListDetailCollectionView.VisibleRow(id: id, depth: indent, frame: attrs.frame))
                default:
                    break
                }
            }
            sectionRows.sort { $0.frame.minY < $1.frame.minY }
            if let headerFrame {
                sections.append(ItemDropSectionGeometry(
                    key: key,
                    headerFrame: headerFrame,
                    rows: sectionRows
                ))
            }
        }
        guard !sections.isEmpty else { return nil }

        let sourceSubtreeDepth = subtreeDepthOf(sourceId)
        let fallbackBottomY = max(
            collectionView.contentSize.height,
            collectionView.bounds.maxY
        ) + (draggingRowHeight ?? Self.itemDropCueSpace) + Self.itemDropBottomPadding
        let normalizedTouchY = min(
            max(touch.y, collectionView.bounds.minY),
            fallbackBottomY
        )
        let normalizedTouch = CGPoint(x: touch.x, y: normalizedTouchY)

        return resolvedItemDropTarget(
            sections: sections,
            touch: normalizedTouch,
            sourceSubtreeDepth: sourceSubtreeDepth,
            dragGrabX: dragGrabX,
            dragGrabDepth: dragGrabDepth,
            fallbackBottomY: fallbackBottomY
        )
    }

    func resolvedItemDropTarget(
        sections: [ItemDropSectionGeometry],
        touch: CGPoint,
        sourceSubtreeDepth: Int,
        dragGrabX: CGFloat?,
        dragGrabDepth: Int,
        fallbackBottomY: CGFloat
    ) -> ListDetailCollectionView.ItemDropTarget? {
        let touchY = touch.y

        // 1. Touch INSIDE a row's frame.
        //    Top half  -> gap above; bottom half -> gap below.
        //    Horizontal position drives indent throughout -- no separate nesting zone.
        for section in sections {
            for (i, row) in section.rows.enumerated() {
                guard row.frame.insetBy(dx: 0, dy: -Self.itemDropVerticalPad).contains(touch) else {
                    continue
                }
                let relY = (touchY - row.frame.minY) / max(row.frame.height, 1)
                if relY < 0.5 {
                    let above = i > 0 ? section.rows[i - 1] : nil
                    let indent = chooseIndent(touchX: touch.x,
                                              rowAboveDepth: above?.depth,
                                              rowBelowDepth: row.depth,
                                              sourceSubtreeDepth: sourceSubtreeDepth,
                                              dragGrabX: dragGrabX,
                                              dragGrabDepth: dragGrabDepth)
                    return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                      beforeRowId: row.id,
                                                                      indent: indent))
                }
                let below = i + 1 < section.rows.count ? section.rows[i + 1] : nil
                let indent = chooseIndent(touchX: touch.x,
                                          rowAboveDepth: row.depth,
                                          rowBelowDepth: below?.depth,
                                          sourceSubtreeDepth: sourceSubtreeDepth,
                                          dragGrabX: dragGrabX,
                                          dragGrabDepth: dragGrabDepth)
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                  beforeRowId: below?.id,
                                                                  indent: indent))
            }
        }

        // 2. Touch on a section header.
        for (idx, section) in sections.enumerated() {
            let headerBand = section.headerFrame.insetBy(
                dx: 0,
                dy: -Self.itemDropVerticalPad
            )
            guard headerBand.contains(touch) else { continue }
            let relY = (touchY - section.headerFrame.minY) / max(section.headerFrame.height, 1)
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
            let nextHeaderMinY: CGFloat = {
                for after in sections.dropFirst(idx + 1) {
                    return after.headerFrame.minY
                }
                // Add slack for the removed dragged row so you can still
                // position below the last visible item.
                return fallbackBottomY
            }()
            guard touchY >= section.headerFrame.maxY - Self.itemDropBottomPadding,
                  touchY < nextHeaderMinY else { continue }

            if section.rows.isEmpty {
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                  beforeRowId: nil,
                                                                  indent: 0))
            }

            // Gap above first row.
            if touchY <= section.rows[0].frame.minY + Self.itemDropBottomPadding {
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                  beforeRowId: section.rows[0].id,
                                                                  indent: 0))
            }

            // Gaps between rows / after last row.
            for i in section.rows.indices {
                let current = section.rows[i]
                let below = i + 1 < section.rows.count ? section.rows[i + 1] : nil
                let upper = below?.frame.minY ?? nextHeaderMinY
                guard touchY >= current.frame.maxY - Self.itemDropBottomPadding,
                      touchY < upper + Self.itemDropBottomPadding else { continue }
                let indent = chooseIndent(touchX: touch.x,
                                          rowAboveDepth: current.depth,
                                          rowBelowDepth: below?.depth,
                                          sourceSubtreeDepth: sourceSubtreeDepth,
                                          dragGrabX: dragGrabX,
                                          dragGrabDepth: dragGrabDepth)
                return .gap(ListDetailCollectionView.GapPosition(sectionKey: section.key,
                                                                  beforeRowId: below?.id,
                                                                  indent: indent))
            }
        }

        // If the finger is above the first rendered header band (for example,
        // due fast travel to the very top of the list), treat it as dropping at
        // the very first section's top gap.
        if let firstSection = sections.first,
           touchY < firstSection.headerFrame.maxY - Self.itemDropVerticalPad {
            return .gap(ListDetailCollectionView.GapPosition(
                sectionKey: firstSection.key,
                beforeRowId: firstSection.rows.first?.id,
                indent: 0
            ))
        }

        // If the finger is below the last row (including long empty
        // viewport space), keep targeting the last section's tail.
        if touchY >= fallbackBottomY - Self.itemDropBottomPadding,
           let lastSection = sections.last {
            return .gap(ListDetailCollectionView.GapPosition(
                sectionKey: lastSection.key,
                beforeRowId: nil,
                indent: 0
            ))
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
                              sourceSubtreeDepth: Int,
                              dragGrabX overrideDragGrabX: CGFloat?,
                              dragGrabDepth overrideDragGrabDepth: Int?) -> Int {
        guard let rowAboveDepth = rowAboveDepth else { return 0 }
        let activeGrabX = overrideDragGrabX ?? dragGrabX
        let activeGrabDepth = overrideDragGrabDepth ?? dragGrabDepth
        let raw: Int
        if let grabX = activeGrabX {
            raw = activeGrabDepth + Int(((touchX - grabX) / ListDetailLayout.indentStep).rounded())
        } else {
            raw = Int(floor((touchX - ListDetailLayout.leadingEdge) / ListDetailLayout.indentStep))
        }
        let maxByAbove = rowAboveDepth + 1
        let maxIndent = min(maxByAbove, ListsNesting.maxDisplayDepth)
        let minIndent = max(0, min(rowBelowDepth ?? 0, maxIndent))
        return max(minIndent, min(raw, maxIndent))
    }
}
