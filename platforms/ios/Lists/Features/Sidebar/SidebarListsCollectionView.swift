import SwiftUI
import UIKit

/// UIKit-backed renderer for the "My Lists" tree, replacing SwiftUI's `List`
/// so the sidebar gets the same hierarchical long-press drag-and-drop as the
/// items inside a list (see `ListDetailCollectionView`). A single section of
/// list rows + a pinned, inert "Recently Deleted" footer.
///
/// Unlike the item collection view this one does **not** scroll: it reports
/// its full content height via `intrinsicContentSize` and lives inside the
/// sidebar's outer `ScrollView`, exactly like the old non-scrolling `List`.
///
/// Visual parity is preserved by hosting the existing `SidebarRow` inside
/// `UIHostingConfiguration` cells; UICollectionView contributes the gesture
/// and reorder semantics.

struct SidebarListsCollectionView: UIViewRepresentable {
    let store: ItemStore
    /// All non-deleted lists, passed from the host. Reading `store.lists` in
    /// the host's body is what makes SwiftUI re-run `updateUIView` when the
    /// list set changes (add / delete / rename / load) — the coordinator
    /// builds its tree from these.
    let lists: [ItemList]
    /// Ids of expandable lists whose children are currently hidden.
    let collapsed: Set<String>
    let deletedCount: Int
    let itemTypePolicy: ItemTypePolicy
    /// Item move mode turns the sidebar into a destination-navigation surface:
    /// list taps and expand/collapse stay available, while list management
    /// gestures and Recently Deleted are hidden.
    var isMoveMode: Bool = false
    /// Bridge for the FAB-drag-to-list create path (see `SidebarListsBridge`).
    let bridge: SidebarListsBridge
    /// The collection view's measured content height, reported back to the host
    /// so the non-scrolling view can size itself inside the outer ScrollView
    /// without a re-entrant synchronous layout.
    @Binding var measuredHeight: CGFloat

    let onTapList: (ItemList) -> Void
    let onToggleCollapse: (String) -> Void
    let onTapRecentlyDeleted: () -> Void
    let onNewSubList: (ItemList) -> Void
    let onMoveTo: (ItemList) -> Void
    let onEditList: (ItemList) -> Void
    let onDeleteList: (String) -> Void

    func makeUIView(context: Context) -> UICollectionView {
        let cv = SelfSizingListsCollectionView(frame: .zero, collectionViewLayout: Self.makeLayout(coordinator: context.coordinator))
        cv.backgroundColor = .clear
        cv.isScrollEnabled = false
        cv.allowsSelection = false
        cv.delegate = context.coordinator
        cv.dragDelegate = context.coordinator
        cv.dropDelegate = context.coordinator
        cv.dragInteractionEnabled = !isMoveMode
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        cv.addGestureRecognizer(tap)
        // The measurement already runs on a fresh main-queue turn, so it is safe
        // to write the height through to SwiftUI state here.
        let heightBinding = _measuredHeight
        cv.onContentHeightChange = { height in
            if heightBinding.wrappedValue != height { heightBinding.wrappedValue = height }
        }
        context.coordinator.parent = self
        bridge.coordinator = context.coordinator
        context.coordinator.setupDataSource(for: cv)
        context.coordinator.applySnapshot(animated: false)
        return cv
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        bridge.coordinator = context.coordinator
        uiView.allowsSelection = false
        uiView.dragInteractionEnabled = !isMoveMode
        context.coordinator.applySnapshot(animated: true)
    }

    /// Report the height SwiftUI should give this non-scrolling view. We return
    /// the height measured during the collection view's own layout pass (see
    /// `SelfSizingListsCollectionView`) — a pure cache read, with NO forced
    /// layout here, which is what keeps the hosted SwiftUI cells from
    /// re-entering the update cycle. Until the first measurement lands the
    /// height is 0; the layout pass then reports the real height and SwiftUI
    /// re-measures.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICollectionView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: measuredHeight)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func makeLayout(coordinator: Coordinator) -> UICollectionViewLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        config.backgroundColor = .clear
        config.trailingSwipeActionsConfigurationProvider = { [weak coordinator] indexPath in
            coordinator?.trailingSwipeActions(for: indexPath)
        }
        config.leadingSwipeActionsConfigurationProvider = { [weak coordinator] indexPath in
            coordinator?.leadingSwipeActions(for: indexPath)
        }
        // Build the section by hand (rather than `.list(using:)`) so we can zero
        // the inset-grouped section's default insets. The ~30pt top inset is
        // what opens the dead gap under the "My Lists" header; the ~16pt side
        // insets make the card narrower than the tiles above it. Zeroing both
        // lets the host pad the card to exactly match the tiles' 16pt margin
        // while keeping the rounded-card styling of `.insetGrouped`.
        return UICollectionViewCompositionalLayout { _, env in
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: env)
            section.contentInsets.top = 0
            section.contentInsets.leading = 0
            section.contentInsets.trailing = 0
            return section
        }
    }
}

// MARK: - Models

extension SidebarListsCollectionView {
    enum Section: Hashable { case main }

    enum Row: Hashable {
        case list(id: String, depth: Int)
        case recentlyDeleted
    }

    /// One row in the flattened sidebar tree.
    typealias TreeRow = ListHierarchy.FlatRow
}

// MARK: - Coordinator

extension SidebarListsCollectionView {
    final class Coordinator: NSObject,
                             UICollectionViewDelegate,
                             UICollectionViewDragDelegate,
                             UICollectionViewDropDelegate,
                             UIGestureRecognizerDelegate {
        var parent: SidebarListsCollectionView?
        var dataSource: UICollectionViewDiffableDataSource<Section, Row>!
        weak var collectionView: UICollectionView?
        /// Render state at the last apply, keyed by row — lets us reconfigure
        /// only the list rows whose visible content (name / count / collapse)
        /// changed, since their diffable identity stays stable across edits.
        private var renderedState: [Row: RowState] = [:]

        // Drag/drop state
        private var draggingId: String?
        private var draggingRowHeight: CGFloat?
        /// The dragged row is removed from the snapshot once the drag actually
        /// moves (first drop-session update), not on the bare lift — the
        /// long-press is shared with the context menu, so hiding on lift would
        /// blank the row when the menu opens.
        private var dragSourceHidden = false
        /// Finger x at lift + the lifted row's depth — indent during the drag
        /// is chosen from horizontal travel relative to these, not absolute
        /// screen x (see `chooseIndent`).
        private var dragGrabX: CGFloat?
        private var dragGrabDepth = 0
        private var dropTarget: DropTarget?
        private var dropCueView: UIView?
        private var highlightedNestId: String?

        /// Where a drag will land: nested INTO a row, or in a GAP between rows
        /// at a chosen indent (vertical picks the gap, horizontal the indent).
        enum DropTarget: Equatable {
            case nestInto(String)
            case gap(beforeId: String?, indent: Int)
        }

        /// Drag-nest is capped at this depth to match items (top/child/
        /// grandchild). Deeper trees stay reachable via "Move to…".
        private static let maxDepth = ListsNesting.maxDisplayDepth
        /// Indent step in points — matches `SidebarRow`'s per-level leading.
        private static let indentStep: CGFloat = ListsNesting.indentStep
        /// Trailing region that toggles a list's child visibility instead of
        /// navigating. Matches the visible chevron column plus comfortable tap
        /// padding.
        private static let disclosureTapWidth: CGFloat = 56

        private struct RowState: Equatable {
            let name: String
            let color: String
            let icon: String
            let count: Int
            let hasChildren: Bool
            let isCollapsed: Bool
        }

        // MARK: Tree

        /// Depth-tagged flatten of the non-deleted list tree, honoring the
        /// per-list collapse state.
        func flatTreeRows() -> [TreeRow] {
            guard let parent else { return [] }
            // While a drag is moving, omit the dragged subtree so its source
            // space closes up like a normal reorder.
            let hiddenId = dragSourceHidden ? draggingId : nil
            return ListHierarchy.flattenedRows(
                in: parent.lists,
                expanded: { !parent.collapsed.contains($0) },
                excludingSubtree: hiddenId
            )
        }

        private func rowState(for list: ItemList, hasChildren: Bool) -> RowState {
            RowState(
                name: list.name,
                color: list.color.rawValue,
                icon: list.icon,
                count: openItemCount(for: list.id),
                hasChildren: hasChildren,
                isCollapsed: parent?.collapsed.contains(list.id) ?? false
            )
        }

        private func openItemCount(for listId: String) -> Int {
            guard let parent else { return 0 }
            return parent.store.openItemCount(in: listId, itemTypePolicy: parent.itemTypePolicy)
        }

        // MARK: Data source

        func setupDataSource(for cv: UICollectionView) {
            self.collectionView = cv
            let listReg = makeListReg()
            let deletedReg = makeRecentlyDeletedReg()
            dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: cv) {
                cv, indexPath, row in
                switch row {
                case .list:
                    return cv.dequeueConfiguredReusableCell(using: listReg, for: indexPath, item: row)
                case .recentlyDeleted:
                    return cv.dequeueConfiguredReusableCell(using: deletedReg, for: indexPath, item: row)
                }
            }
        }

        func applySnapshot(animated: Bool) {
            guard parent != nil else { return }
            let rows = flatTreeRows()

            var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
            snapshot.appendSections([.main])
            snapshot.appendItems(rows.map { .list(id: $0.list.id, depth: $0.depth) }, toSection: .main)
            if parent?.isMoveMode != true {
                snapshot.appendItems([.recentlyDeleted], toSection: .main)
            }

            // Reconfigure list rows whose visible content changed but whose
            // identity (id + depth) did not — counts, renames, collapse state.
            let previous = Set(dataSource.snapshot().itemIdentifiers)
            var nextState: [Row: RowState] = [:]
            var changed: [Row] = []
            for tree in rows {
                let row = Row.list(id: tree.list.id, depth: tree.depth)
                let state = rowState(for: tree.list, hasChildren: tree.hasChildren)
                nextState[row] = state
                if previous.contains(row), renderedState[row] != state {
                    changed.append(row)
                }
            }
            renderedState = nextState
            if !changed.isEmpty {
                snapshot.reconfigureItems(changed)
            }

            dataSource.apply(snapshot, animatingDifferences: animated)
            (collectionView as? SelfSizingListsCollectionView)?.setNeedsHeightMeasure()
        }

        private func makeListReg() -> UICollectionView.CellRegistration<SidebarListCollectionCell, Row> {
            UICollectionView.CellRegistration { [weak self] cell, _, row in
                guard case .list(let id, let depth) = row,
                      let parent = self?.parent,
                      let coordinator = self,
                      let list = parent.lists.first(where: { $0.id == id }) else { return }
                let hasChildren = parent.lists.contains { $0.parentId == id && $0.deletedAt == nil }
                let isCollapsed = parent.collapsed.contains(id)
                let count = coordinator.openItemCount(for: id)
                let onTap = parent.onTapList
                cell.contentConfiguration = UIHostingConfiguration {
                    SidebarListCellContent(
                        list: list,
                        depth: depth,
                        hasChildren: hasChildren,
                        isCollapsed: isCollapsed,
                        count: count
                    )
                }
                .margins(.vertical, 7)
                .margins(.horizontal, 16)
                var background = UIBackgroundConfiguration.listCell()
                if coordinator.highlightedNestId == id {
                    background.backgroundColor = UIColor(ListsTokens.listColor(list.color)).withAlphaComponent(0.30)
                }
                cell.backgroundConfiguration = background
                cell.accessibilityIdentifier = "sidebar.list.\(id)"
                cell.accessibilityLabel = count > 0 ? "\(list.name), \(count)" : list.name
                cell.accessibilityTraits.insert(.button)
                cell.onAccessibilityActivate = { onTap(list) }
                if hasChildren {
                    let actionName = isCollapsed ? "Expand" : "Collapse"
                    cell.accessibilityCustomActions = [
                        UIAccessibilityCustomAction(name: actionName) { _ in
                            parent.onToggleCollapse(id)
                            return true
                        }
                    ]
                } else {
                    cell.accessibilityCustomActions = nil
                }
            }
        }

        private func makeRecentlyDeletedReg() -> UICollectionView.CellRegistration<SidebarListCollectionCell, Row> {
            UICollectionView.CellRegistration { [weak self] cell, _, _ in
                guard let parent = self?.parent else { return }
                let count = parent.deletedCount
                let onTap = parent.onTapRecentlyDeleted
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack(spacing: 0) {
                        SidebarRow(
                            icon: "trash.fill",
                            hue: Color(.systemGray4),
                            label: "Recently Deleted",
                            count: count > 0 ? count : nil,
                            iconShape: .roundedSquare,
                            iconGlyphColor: Color(.secondaryLabel)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        DecorativeChevron()
                    }
                }
                .margins(.vertical, 7)
                .margins(.horizontal, 16)
                cell.accessibilityIdentifier = "sidebar.recentlyDeleted"
                cell.accessibilityLabel = count > 0 ? "Recently Deleted, \(count)" : "Recently Deleted"
                cell.accessibilityTraits.insert(.button)
                cell.onAccessibilityActivate = onTap
                cell.accessibilityCustomActions = nil
            }
        }

        // MARK: Tap

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  draggingId == nil,
                  let collectionView = recognizer.view as? UICollectionView else { return }
            let location = recognizer.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  let row = dataSource.itemIdentifier(for: indexPath),
                  let parent else { return }
            switch row {
            case .list(let id, _):
                guard let list = parent.lists.first(where: { $0.id == id }) else { return }
                if hasChildren(id),
                   let cell = collectionView.cellForItem(at: indexPath) {
                    let pointInCell = cell.convert(location, from: collectionView)
                    if cell.bounds.maxX - pointInCell.x <= Self.disclosureTapWidth {
                        parent.onToggleCollapse(id)
                        return
                    }
                }
                parent.onTapList(list)
            case .recentlyDeleted:
                parent.onTapRecentlyDeleted()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        private func hasChildren(_ id: String) -> Bool {
            parent?.lists.contains { $0.parentId == id && $0.deletedAt == nil } ?? false
        }

        // MARK: Context menu

        /// Long-press-and-dwell menu, mirroring the old `listContextMenu`. The
        /// same long-press also starts a drag if the finger moves; UIKit
        /// multiplexes the two. Suppressed for the Recently Deleted footer and
        /// while item move mode is active.
        func collectionView(_ collectionView: UICollectionView,
                            contextMenuConfigurationForItemAt indexPath: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
            guard let parent, !parent.isMoveMode,
                  case .list(let id, _) = dataSource.itemIdentifier(for: indexPath),
                  let list = parent.lists.first(where: { $0.id == id }) else { return nil }
            return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in
                guard let parent = self?.parent else { return nil }
                let newSub = UIAction(title: "New Sublist",
                                      image: UIImage(systemName: "folder.badge.plus")) { _ in
                    parent.onNewSubList(list)
                }
                let move = UIAction(title: "Move",
                                    image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")) { _ in
                    parent.onMoveTo(list)
                }
                let edit = UIAction(title: "Edit List",
                                    image: UIImage(systemName: "info.circle")) { _ in
                    parent.onEditList(list)
                }
                let delete = UIAction(title: "Delete List",
                                      image: UIImage(systemName: "trash"),
                                      attributes: .destructive) { _ in
                    parent.onDeleteList(id)
                }
                return UIMenu(children: [newSub, move, edit, delete])
            }
        }

        // MARK: Swipe actions

        func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let parent, !parent.isMoveMode,
                  case .list(let id, _) = dataSource.itemIdentifier(for: indexPath),
                  let list = parent.lists.first(where: { $0.id == id }) else { return nil }
            let onDeleteList = parent.onDeleteList
            let onEditList = parent.onEditList

            let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                onDeleteList(id)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            delete.backgroundColor = .systemRed

            let edit = UIContextualAction(style: .normal, title: "Edit List") { _, _, completion in
                onEditList(list)
                completion(true)
            }
            edit.image = UIImage(systemName: "info.circle")
            edit.backgroundColor = .systemGray

            let config = UISwipeActionsConfiguration(actions: [delete, edit])
            config.performsFirstActionWithFullSwipe = true
            return config
        }

        /// Leading swipe — the list-side counterparts to the item rows' swipes,
        /// reusing the same handlers as the context menu's "Move to…" / "New
        /// Sub-List Here".
        func leadingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let parent, !parent.isMoveMode,
                  case .list(let id, _) = dataSource.itemIdentifier(for: indexPath),
                  let list = parent.lists.first(where: { $0.id == id }) else { return nil }
            let onMoveTo = parent.onMoveTo
            let onNewSubList = parent.onNewSubList

            let move = UIContextualAction(style: .normal, title: "Move") { _, _, completion in
                onMoveTo(list)
                completion(true)
            }
            move.image = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            move.backgroundColor = UIColor(ListsTokens.accent)

            let newSub = UIContextualAction(style: .normal, title: "New Sublist") { _, _, completion in
                onNewSubList(list)
                completion(true)
            }
            newSub.image = UIImage(systemName: "folder.badge.plus")
            newSub.backgroundColor = .systemGreen

            let config = UISwipeActionsConfiguration(actions: [move, newSub])
            config.performsFirstActionWithFullSwipe = false
            return config
        }

        // MARK: Drag

        func collectionView(_ collectionView: UICollectionView,
                            itemsForBeginning session: UIDragSession,
                            at indexPath: IndexPath) -> [UIDragItem] {
            guard let parent, !parent.isMoveMode,
                  case .list(let id, let depth) = dataSource.itemIdentifier(for: indexPath) else { return [] }
            let drag = UIDragItem(itemProvider: NSItemProvider())
            drag.localObject = id
            draggingId = id
            dragSourceHidden = false
            dragGrabX = session.location(in: collectionView).x
            dragGrabDepth = depth
            // Cell-independent preview: `drawHierarchy(afterScreenUpdates:true)`
            // is the one snapshot path that captures SwiftUI-hosted content
            // (snapshotView / layer.render come back black). Lets the source
            // row be hidden mid-drag without killing the lifted preview.
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
            clearDropTarget()
            return [drag]
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
            // Async so this runs after any pending update; restore the source
            // row only if the drag was cancelled (a committed drop already
            // cleared draggingId in performDropWith).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let needsRestore = self.draggingId != nil && self.dragSourceHidden
                self.draggingId = nil
                self.draggingRowHeight = nil
                self.dragSourceHidden = false
                self.dragGrabX = nil
                self.clearDropTarget()
                if needsRestore { self.applySnapshot(animated: true) }
            }
        }

        // MARK: Drop

        func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
            parent?.isMoveMode != true && session.localDragSession != nil
        }

        func collectionView(_ collectionView: UICollectionView,
                            dropSessionDidUpdate session: UIDropSession,
                            withDestinationIndexPath destination: IndexPath?) -> UICollectionViewDropProposal {
            guard let sourceId = draggingId else {
                return UICollectionViewDropProposal(operation: .cancel)
            }
            // Hide the source now that the drag is actually moving.
            if !dragSourceHidden {
                dragSourceHidden = true
                applySnapshot(animated: true)
            }
            let touch = session.location(in: collectionView)
            let target = resolvedDropTarget(in: collectionView, touch: touch, sourceId: sourceId)
            setDropTarget(target, in: collectionView)
            // `.unspecified` (not `.insertAtDestinationIndexPath`): the reorder is
            // committed by `performListReorder` applying our own diffable
            // snapshot, so UIKit must NOT also reserve an insertion slot — the
            // count mismatch between its reserved slot and our snapshot crashes
            // on drop. Mirrors the working item reorder in ListDetailCollectionView.
            return UICollectionViewDropProposal(
                operation: target == nil ? .cancel : .move,
                intent: .unspecified
            )
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
            clearDropTarget()
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
            draggingId = nil
            draggingRowHeight = nil
            dragSourceHidden = false
            clearDropTarget()
        }

        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
            guard let item = coordinator.items.first,
                  let id = item.dragItem.localObject as? String else { return }
            let pending = dropTarget
            draggingId = nil
            dragSourceHidden = false
            clearDropTarget()
            if let pending {
                _ = performListReorder(listId: id, dropTarget: pending)
            } else {
                applySnapshot(animated: true)   // no target → restore source
            }
            let finalPath = currentIndexPath(forListId: id)
                ?? coordinator.destinationIndexPath
                ?? IndexPath(item: 0, section: 0)
            coordinator.drop(item.dragItem, toItemAt: finalPath)
        }

        private func currentIndexPath(forListId id: String) -> IndexPath? {
            for row in dataSource.snapshot().itemIdentifiers {
                if case .list(let rid, let depth) = row, rid == id {
                    return dataSource.indexPath(for: .list(id: rid, depth: depth))
                }
            }
            return nil
        }

        // MARK: FAB drag-to-list (no UIDropSession — driven by SidebarListsBridge)

        /// The list id whose row contains `globalPoint`, or nil. Used to resolve
        /// the FAB-drag create target.
        func listIdUnderFABDrag(globalPoint: CGPoint) -> String? {
            guard let cv = collectionView else { return nil }
            let local = cv.convert(globalPoint, from: nil)
            for row in dataSource.snapshot().itemIdentifiers {
                guard case .list(let id, _) = row,
                      let ip = dataSource.indexPath(for: row),
                      let frame = cv.collectionViewLayout.layoutAttributesForItem(at: ip)?.frame,
                      frame.contains(local) else { continue }
                return id
            }
            return nil
        }

        /// Highlight the list under the FAB-drag point with the existing
        /// `.nestInto` cue (a tinted rounded rect over the row). Returns the id
        /// under the finger so the host can also tint the FAB to that list.
        @discardableResult
        func updateFABDragHighlight(globalPoint: CGPoint) -> String? {
            guard let cv = collectionView else { return nil }
            if let id = listIdUnderFABDrag(globalPoint: globalPoint) {
                setDropTarget(.nestInto(id), in: cv)
                return id
            }
            clearDropTarget()
            return nil
        }

        func cancelFABDragCue() {
            clearDropTarget()
        }

        // MARK: Drop target resolution

        private func resolvedDropTarget(in cv: UICollectionView, touch: CGPoint, sourceId: String) -> DropTarget? {
            var rows: [(id: String, depth: Int, frame: CGRect)] = []
            for row in dataSource.snapshot().itemIdentifiers {
                guard case .list(let id, let depth) = row,
                      id != sourceId, !isDescendant(id, of: sourceId),
                      let ip = dataSource.indexPath(for: row),
                      let attrs = cv.collectionViewLayout.layoutAttributesForItem(at: ip) else { continue }
                rows.append((id, depth, attrs.frame))
            }
            rows.sort { $0.frame.minY < $1.frame.minY }
            guard !rows.isEmpty else { return .gap(beforeId: nil, indent: 0) }

            let leading = contentLeading(in: cv)
            let subtreeDepth = subtreeDepthOf(sourceId)

            // Touch inside a row: center band nests, halves are gaps.
            for (i, row) in rows.enumerated() {
                guard row.frame.insetBy(dx: 0, dy: -2).contains(touch) else { continue }
                let relY = (touch.y - row.frame.minY) / max(row.frame.height, 1)
                if relY >= 0.36, relY <= 0.64, canNest(sourceId, inside: row.id) {
                    return .nestInto(row.id)
                }
                if relY < 0.5 {
                    let above = i > 0 ? rows[i - 1] : nil
                    return .gap(beforeId: row.id,
                                indent: chooseIndent(touchX: touch.x, leading: leading,
                                                     rowAboveDepth: above?.depth, rowBelowDepth: row.depth,
                                                     sourceSubtreeDepth: subtreeDepth))
                }
                let below = i + 1 < rows.count ? rows[i + 1] : nil
                return .gap(beforeId: below?.id,
                            indent: chooseIndent(touchX: touch.x, leading: leading,
                                                 rowAboveDepth: row.depth, rowBelowDepth: below?.depth,
                                                 sourceSubtreeDepth: subtreeDepth))
            }

            // Above the first row → top.
            if let first = rows.first, touch.y < first.frame.minY {
                return .gap(beforeId: first.id, indent: 0)
            }
            // Below the last row → end, indent from touch.x.
            return .gap(beforeId: nil,
                        indent: chooseIndent(touchX: touch.x, leading: leading,
                                             rowAboveDepth: rows.last?.depth, rowBelowDepth: nil,
                                             sourceSubtreeDepth: subtreeDepth))
        }

        /// Maps a horizontal touch to a target indent: the lifted row's depth
        /// plus one level per `indentStep` of horizontal travel from the grab
        /// point (relative motion — grab anywhere on the row, nudge left/right
        /// to out/indent), clamped by the row above (can't be deeper than its
        /// child), the dragged subtree's own depth (can't push children past
        /// the cap), and the row below (can't sit shallower than it).
        private func chooseIndent(touchX: CGFloat, leading: CGFloat,
                                  rowAboveDepth: Int?, rowBelowDepth: Int?,
                                  sourceSubtreeDepth: Int) -> Int {
            guard let rowAboveDepth else { return 0 }
            let raw: Int
            if let grabX = dragGrabX {
                raw = dragGrabDepth + Int(((touchX - grabX) / Self.indentStep).rounded())
            } else {
                raw = Int(floor((touchX - leading) / Self.indentStep))
            }
            let maxByAbove = min(rowAboveDepth + 1, Self.maxDepth)
            let maxBySubtree = max(0, Self.maxDepth - sourceSubtreeDepth)
            let maxIndent = min(maxByAbove, maxBySubtree)
            let minIndent = max(0, min(rowBelowDepth ?? 0, maxIndent))
            return max(minIndent, min(raw, maxIndent))
        }

        /// New parentId for a gap drop: walk up the row-above's ancestor chain
        /// by `(aboveDepth + 1 - indent)` levels. nil = top level.
        private func computeNewParentId(beforeId: String?, indent: Int, sourceId: String) -> String? {
            guard indent > 0, let parent else { return nil }
            var rowAbove: (id: String, depth: Int)?
            for row in dataSource.snapshot().itemIdentifiers {
                guard case .list(let id, let depth) = row else { continue }
                if let stop = beforeId, id == stop { break }
                if id != sourceId, !isDescendant(id, of: sourceId) { rowAbove = (id, depth) }
            }
            guard let above = rowAbove else { return nil }
            let stepsUp = above.depth + 1 - indent
            if stepsUp <= 0 { return above.id }
            var current: String? = above.id
            for _ in 0..<stepsUp {
                guard let id = current else { return nil }
                current = parent.lists.first(where: { $0.id == id })?.parentId
            }
            return current
        }

        // MARK: Commit

        @discardableResult
        private func performListReorder(listId: String, dropTarget: DropTarget) -> Bool {
            guard let parent else { return false }
            // Full tree order (including collapsed children) so per-parent
            // position renumbering in the store stays complete and collision-free.
            var order = fullFlatOrderIds()
            order.removeAll { $0 == listId }

            let newParentId: String?
            let insertIndex: Int
            switch dropTarget {
            case .nestInto(let targetId):
                guard canNest(listId, inside: targetId),
                      let targetIdx = order.firstIndex(of: targetId) else { return false }
                newParentId = targetId
                var idx = targetIdx + 1
                while idx < order.count, isDescendant(order[idx], of: targetId) { idx += 1 }
                insertIndex = idx
                // Expand the target so the freshly-nested list is visible.
                if parent.collapsed.contains(targetId) { parent.onToggleCollapse(targetId) }
            case .gap(let beforeId, let indent):
                newParentId = computeNewParentId(beforeId: beforeId, indent: indent, sourceId: listId)
                if let beforeId, let bIdx = order.firstIndex(of: beforeId) {
                    insertIndex = bIdx
                } else {
                    insertIndex = order.count
                }
            }
            order.insert(listId, at: min(max(insertIndex, 0), order.count))

            guard parent.store.applyListReorderSync(movedId: listId, toParent: newParentId, flatOrderedIds: order) else {
                applySnapshot(animated: true)   // rejected (cycle) — restore
                return false
            }
            applySnapshot(animated: false)
            return true
        }

        /// Depth-first ids of every non-deleted list, ignoring collapse.
        private func fullFlatOrderIds() -> [String] {
            guard let parent else { return [] }
            return ListHierarchy.flattenedIds(in: parent.lists)
        }

        // MARK: Drop cue overlay

        private func setDropTarget(_ target: DropTarget?, in cv: UICollectionView) {
            guard dropTarget != target else { return }
            let oldHighlight = highlightedNestId
            highlightedNestId = {
                guard case .nestInto(let id) = target else { return nil }
                return id
            }()
            dropTarget = target
            reconfigureHighlightRows(oldHighlight, highlightedNestId)
            updateCue(in: cv)
        }

        private func clearDropTarget() {
            let oldHighlight = highlightedNestId
            dropTarget = nil
            highlightedNestId = nil
            reconfigureHighlightRows(oldHighlight, nil)
            dropCueView?.removeFromSuperview()
            dropCueView = nil
        }

        private func updateCue(in cv: UICollectionView) {
            guard let target = dropTarget else {
                dropCueView?.removeFromSuperview(); dropCueView = nil; return
            }
            cv.layoutIfNeeded()
            let color = UIColor(ListsTokens.accent)
            switch target {
            case .nestInto:
                dropCueView?.removeFromSuperview()
                dropCueView = nil
            case .gap(let beforeId, let indent):
                guard let gy = gapY(beforeId: beforeId, in: cv) else { return }
                let leading = contentLeading(in: cv) + CGFloat(indent) * Self.indentStep
                let width = max(0, cv.bounds.width - leading - 16)
                showCue(frame: CGRect(x: leading, y: gy - 2, width: width, height: 4),
                        color: color,
                        in: cv)
            }
        }

        private func showCue(frame: CGRect,
                             color: UIColor,
                             in cv: UICollectionView) {
            let cue: UIView
            if let existing = dropCueView {
                cue = existing
            } else {
                let v = UIView()
                v.isUserInteractionEnabled = false
                v.accessibilityIdentifier = "sidebar.drop.cue"
                v.layer.masksToBounds = true
                cv.addSubview(v)
                dropCueView = v
                cue = v
            }
            cue.layer.cornerRadius = 2
            cue.backgroundColor = color.withAlphaComponent(0.9)
            cue.layer.borderWidth = 0
            cue.layer.mask = nil
            UIView.performWithoutAnimation {
                cue.frame = frame
                cue.isHidden = false
                cue.alpha = 1
                cv.bringSubviewToFront(cue)
            }
        }

        private func frameForList(_ id: String, in cv: UICollectionView) -> CGRect? {
            for row in dataSource.snapshot().itemIdentifiers {
                guard case .list(let rid, let depth) = row, rid == id,
                      let ip = dataSource.indexPath(for: .list(id: rid, depth: depth)) else { continue }
                return cv.collectionViewLayout.layoutAttributesForItem(at: ip)?.frame
            }
            return nil
        }

        private func gapY(beforeId: String?, in cv: UICollectionView) -> CGFloat? {
            if let beforeId { return frameForList(beforeId, in: cv)?.minY }
            var maxY: CGFloat?
            for row in dataSource.snapshot().itemIdentifiers {
                guard case .list = row, let ip = dataSource.indexPath(for: row),
                      let f = cv.collectionViewLayout.layoutAttributesForItem(at: ip)?.frame else { continue }
                maxY = max(maxY ?? 0, f.maxY)
            }
            return maxY
        }

        /// x where a depth-0 row's content begins, in collection-view coords.
        private func contentLeading(in cv: UICollectionView) -> CGFloat {
            (cv.visibleCells.map(\.frame.minX).min() ?? 16) + 16
        }

        private func reconfigureHighlightRows(_ oldId: String?, _ newId: String?) {
            let rows = [oldId, newId]
                .compactMap { $0 }
                .reduce(into: [Row]()) { result, id in
                    if let row = rowForListId(id), !result.contains(row) {
                        result.append(row)
                    }
                }
            guard !rows.isEmpty else { return }
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(rows)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        private func rowForListId(_ id: String) -> Row? {
            dataSource.snapshot().itemIdentifiers.first { row in
                if case .list(let rowId, _) = row { return rowId == id }
                return false
            }
        }

        // MARK: Tree helpers

        private func isDescendant(_ candidateId: String, of ancestorId: String) -> Bool {
            guard let parent else { return false }
            return ListHierarchy.isDescendant(candidateId, of: ancestorId, in: parent.lists)
        }

        private func subtreeDepthOf(_ id: String) -> Int {
            guard let parent else { return 0 }
            return ListHierarchy.subtreeDepth(of: id, in: parent.lists)
        }

        private func canNest(_ sourceId: String, inside targetId: String) -> Bool {
            guard let parent else { return false }
            return ListHierarchy.canNest(
                sourceId,
                inside: targetId,
                in: parent.lists,
                maxDepth: Self.maxDepth
            )
        }
    }
}
