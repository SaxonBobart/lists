import SwiftUI
import UIKit

/// UIKit-backed renderer for the body of `ListDetailView`. Replaces
/// SwiftUI's `List` so we get hierarchical drag-and-drop that SwiftUI's
/// flat `.onMove` can't express:
///
/// - Item drags carry across sections. The (touch.x, touch.y) jointly
///   pick a drop slot: vertical position picks which gap, horizontal
///   position picks the indent at that gap (one 24pt step per depth).
/// - Section header drags only land at another section header position.
///   Drop hints never fall between items.
/// - Long-press on an item opens a UIKit context menu. Long-press on a
///   section header initiates the section drag (no context menu).
///
/// Visual parity is preserved by hosting the existing SwiftUI rows
/// (`ItemRow`, `CVSectionHeaderRow`, etc.) inside `UIHostingConfiguration`
/// cells. UICollectionView contributes the gesture and reorder semantics;
/// SwiftUI handles the pixels.

// Public sentinel — must match the equivalent constant in ListDetailView
// so the synthetic "Others" bucket round-trips correctly between the two
// layers.
let listDetailUncategorizedKey = "__uncategorized__"

struct ListDetailCollectionView: UIViewRepresentable {
    let store: ItemStore
    let listId: String
    var prefs: ListViewPreferences
    let listColor: Color
    @Binding var inSelectMode: Bool
    @Binding var selection: Set<UUID>
    let lingeringIds: Set<UUID>

    let onToggleItem: (Item) -> Void
    let onIncrementHabit: (Item) -> Void
    let onSelectToggle: (UUID) -> Void
    let onPromptDeleteSection: (UUID, String) -> Void
    let onSoftDeleteSubList: (String) -> Void
    let onSoftDeleteItem: (UUID) -> Void
    let onPromoteOthers: (String) -> Void
    let onRenameSection: (UUID, String) -> Void
    let onShowItemDetail: (Item) -> Void
    let onOpenSubList: (ItemList) -> Void

    var list: ItemList? {
        store.lists.first(where: { $0.id == listId })
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = makeLayout(context: context)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.delegate = context.coordinator
        cv.dragDelegate = context.coordinator
        cv.dropDelegate = context.coordinator
        cv.dragInteractionEnabled = true
        cv.allowsSelection = false
        cv.alwaysBounceVertical = true
        cv.contentInsetAdjustmentBehavior = .automatic

        context.coordinator.parent = self
        context.coordinator.setupDataSource(for: cv)
        context.coordinator.applySnapshot(animated: false)
        return cv
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        uiView.allowsSelection = false
        context.coordinator.parent = self
        context.coordinator.applySnapshot(animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func makeLayout(context: Context) -> UICollectionViewLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        config.backgroundColor = .clear
        config.trailingSwipeActionsConfigurationProvider = { [weak coord = context.coordinator] indexPath in
            coord?.trailingSwipeActions(for: indexPath)
        }
        config.leadingSwipeActionsConfigurationProvider = { [weak coord = context.coordinator] indexPath in
            coord?.leadingSwipeActions(for: indexPath)
        }
        return UICollectionViewCompositionalLayout.list(using: config)
    }
}

// MARK: - Models

extension ListDetailCollectionView {
    enum SectionKey: Hashable, Sendable {
        case subLists
        case section(key: String)
    }

    enum RowItem: Hashable, Sendable {
        case subListsHeader
        case subListChild(id: String)
        case sectionHeader(key: String)
        case sectionDropPlaceholder(id: String)
        case item(id: UUID, indent: Int)
    }
}

// MARK: - Coordinator

extension ListDetailCollectionView {
    final class Coordinator: NSObject,
                              UICollectionViewDelegate,
                              UICollectionViewDragDelegate,
                              UICollectionViewDropDelegate {
        var parent: ListDetailCollectionView?
        var dataSource: UICollectionViewDiffableDataSource<SectionKey, RowItem>!
        weak var collectionView: UICollectionView?
        /// Set while a section header is being dragged. When non-nil, the
        /// snapshot rebuild drops every item from this section so the
        /// floating section travels alone with nothing visually lingering
        /// at its source position.
        private var draggingSectionKey: String?
        private var draggingSectionHeight: CGFloat = 44
        private var draggingItemId: UUID?
        /// Natural content width (checkbox + text + trailing indicators) of
        /// the row being dragged, measured once at lift. The placement cue
        /// hugs this width instead of spanning the full row.
        private var draggingContentWidth: CGFloat?
        private var sectionDropTarget: SectionDropTarget?
        private var itemDropTarget: ItemDropTarget?
        private var itemDropCueView: UIView?
        private var itemDropShiftedCells: [UICollectionViewCell] = []

        private enum SectionDropTarget: Hashable {
            case before(String)
            case afterLast
        }

        /// Unified drop target model: a drag either lands INTO a row (force-nest
        /// under it) or in a GAP between rows. Vertical position picks the gap;
        /// horizontal position picks the indent at that gap.
        private enum ItemDropTarget: Hashable {
            case nestInto(UUID)
            case gap(GapPosition)
        }

        private struct GapPosition: Hashable {
            let sectionKey: String
            /// Row this gap sits ABOVE in the section's flat-with-children
            /// order. `nil` means "end of section".
            let beforeRowId: UUID?
            /// Chosen depth at this gap, from touch.x. 0 = top-level, 2 = cap.
            let indent: Int
        }

        private struct VisibleRow {
            let id: UUID
            let depth: Int
            let frame: CGRect
        }

        private enum ItemDropCueStyle: Equatable {
            case placement
            case nesting
        }

        private static let sectionDropPlaceholderId = "section-drop-placeholder"
        private static let itemDropCueHeight: CGFloat = 26
        private static let itemDropCueSpace: CGFloat = 34

        // MARK: Data source setup

        func setupDataSource(for cv: UICollectionView) {
            self.collectionView = cv

            let subListsHeader = makeSubListsHeaderReg()
            let subListChild = makeSubListChildReg()
            let sectionHeader = makeSectionHeaderReg()
            let sectionDropPlaceholder = makeSectionDropPlaceholderReg()
            let item = makeItemReg()

            dataSource = UICollectionViewDiffableDataSource<SectionKey, RowItem>(collectionView: cv) {
                cv, indexPath, row in
                switch row {
                case .subListsHeader:
                    return cv.dequeueConfiguredReusableCell(using: subListsHeader, for: indexPath, item: row)
                case .subListChild:
                    return cv.dequeueConfiguredReusableCell(using: subListChild, for: indexPath, item: row)
                case .sectionHeader:
                    return cv.dequeueConfiguredReusableCell(using: sectionHeader, for: indexPath, item: row)
                case .sectionDropPlaceholder:
                    return cv.dequeueConfiguredReusableCell(using: sectionDropPlaceholder, for: indexPath, item: row)
                case .item:
                    return cv.dequeueConfiguredReusableCell(using: item, for: indexPath, item: row)
                }
            }
        }

        private func makeSubListsHeaderReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, _, _ in
                cell.transform = .identity
                guard let parent = self?.parent else { return }
                let listId = parent.listId
                let expanded = parent.prefs.subListsExpanded(for: listId)
                let prefs = parent.prefs
                cell.contentConfiguration = UIHostingConfiguration {
                    CVSubListsHeaderRow(expanded: expanded) { [weak self] in
                        prefs.setSubListsExpanded(!expanded, for: listId)
                        self?.applySnapshot(animated: true, reconfigure: [.subListsHeader])
                    }
                }
                .margins(.all, 0)
                cell.accessibilityIdentifier = "list.sublists.header"
            }
        }

        private func makeSubListChildReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, _, row in
                cell.transform = .identity
                guard case .subListChild(let id) = row,
                      let parent = self?.parent,
                      let child = parent.store.lists.first(where: { $0.id == id }) else { return }
                let count = parent.store.items.filter { $0.listId == child.id && !$0.done && $0.deletedAt == nil }.count
                let onOpen = parent.onOpenSubList
                cell.contentConfiguration = UIHostingConfiguration {
                    CVSubListChildRow(child: child, openItemCount: count, onOpen: { onOpen(child) })
                }
                .margins(.all, 0)
                cell.accessibilityIdentifier = "list.sublist.\(id)"
            }
        }

        private func makeSectionHeaderReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, indexPath, row in
                cell.transform = .identity
                guard case .sectionHeader(let key) = row,
                      let parent = self?.parent else { return }
                let isOthers = (key == listDetailUncategorizedKey)
                let displayName = parent.sectionDisplayName(for: key) ?? ""
                let listId = parent.listId
                let prefs = parent.prefs
                let expanded = prefs.sectionExpanded(key, in: listId)
                let isFirstRow = (indexPath == IndexPath(item: 0, section: 0))
                let listColor = parent.listColor
                let onPromoteOthers = parent.onPromoteOthers
                let onRenameSection = parent.onRenameSection
                cell.contentConfiguration = UIHostingConfiguration {
                    CVSectionHeaderRow(
                        sectionKey: key,
                        displayName: displayName,
                        isOthers: isOthers,
                        expanded: expanded,
                        showTopDivider: !isFirstRow,
                        listColor: listColor,
                        onToggleExpanded: { [weak self] in
                            prefs.setSectionExpanded(!expanded, sectionId: key, in: listId)
                            self?.applySnapshot(animated: true, reconfigure: [.sectionHeader(key: key)])
                        },
                        onCommitRename: { newName in
                            if isOthers {
                                onPromoteOthers(newName)
                            } else if let uuid = UUID(uuidString: key) {
                                onRenameSection(uuid, newName)
                            }
                        }
                    )
                }
                .margins(.all, 0)
                cell.accessibilityIdentifier = "list.section.\(key)"
            }
        }

        private func makeSectionDropPlaceholderReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, _, _ in
                cell.transform = .identity
                let height = max(self?.draggingSectionHeight ?? 44, 44)
                cell.contentConfiguration = UIHostingConfiguration {
                    CVSectionDropPlaceholder(height: height)
                }
                .margins(.all, 0)
                cell.accessibilityIdentifier = "list.section.dropPlaceholder"
            }
        }

        private func makeItemReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, _, row in
                cell.transform = .identity
                guard case .item(let id, let indent) = row,
                      let parent = self?.parent,
                      let item = parent.store.items.first(where: { $0.id == id }) else { return }
                let store = parent.store
                let inSelectMode = parent.inSelectMode
                let isSelected = parent.selection.contains(id)
                let onToggleItem = parent.onToggleItem
                let onIncrementHabit = parent.onIncrementHabit
                let onSelectToggle = parent.onSelectToggle
                let prefs = parent.prefs
                let listId = parent.listId
                let isExpanded = prefs.itemExpanded(id.uuidString, in: listId)
                cell.contentConfiguration = UIHostingConfiguration {
                    ItemRow(
                        item: item,
                        isOverdue: parent.isOverdue(item),
                        store: store,
                        onToggle: { onToggleItem(item) },
                        onIncrementHabit: { onIncrementHabit(item) },
                        indent: indent,
                        previousSiblingId: nil,
                        previousSiblingParentId: nil,
                        showSubItemIndicator: false,
                        inSelectMode: inSelectMode,
                        isSelected: isSelected,
                        onSelectToggle: { onSelectToggle(id) },
                        showCollapseControl: true,
                        isExpanded: isExpanded,
                        onToggleCollapse: { [weak self] in
                            prefs.setItemExpanded(!isExpanded, itemId: id.uuidString, in: listId)
                            self?.applySnapshot(animated: true, reconfigure: [.item(id: id, indent: indent)])
                        }
                    )
                }
                .margins(.all, 0)
                cell.accessibilityIdentifier = "list.item.\(item.id.uuidString)"
            }
        }

        // MARK: Snapshot

        func applySnapshot(animated: Bool, reconfigure: [RowItem] = []) {
            guard let parent = parent, let list = parent.list else { return }
            guard draggingItemId == nil else { return }

            var snapshot = NSDiffableDataSourceSnapshot<SectionKey, RowItem>()

            // While a section drag is in flight, collapse ONLY the dragged
            // section's items — every other section keeps its body visible
            // so the user can see the surrounding context while reorganising.
            // Section drops draw an explicit placeholder only at real section
            // boundaries, so item rows never open a misleading slot.
            let draggingKey = draggingSectionKey
            let dropTarget = sectionDropTarget

            // Sub-Lists area — stays fully expanded during section drag so
            // the user keeps their bearings.
            let childLists = parent.store.lists
                .filter { $0.parentId == parent.listId && $0.deletedAt == nil }
                .sorted { $0.position < $1.position }
            if !childLists.isEmpty {
                snapshot.appendSections([.subLists])
                snapshot.appendItems([.subListsHeader], toSection: .subLists)
                if parent.prefs.subListsExpanded(for: parent.listId) {
                    snapshot.appendItems(
                        childLists.map { .subListChild(id: $0.id) },
                        toSection: .subLists
                    )
                }
            }

            // Section keys ordered
            let showCompleted = parent.prefs.showCompleted(for: parent.listId)
            let visibleParents = parent.store.items.filter { item in
                item.listId == parent.listId
                    && item.deletedAt == nil
                    && item.parentId == nil
                    && (showCompleted || !item.isComplete || parent.lingeringIds.contains(item.id))
            }
            let namedKeys = list.sections
                .sorted { $0.position < $1.position }
                .map(\.id.uuidString)
            let namedKeysSet = Set(namedKeys)
            // An "orphan" is an item whose section UUID doesn't match any
            // current ListSection — e.g. left over from a since-deleted
            // section. Bucket them into Others so they remain visible and
            // recoverable.
            let isOrphan: (Item) -> Bool = { item in
                guard let s = item.section else { return false }
                return !namedKeysSet.contains(s)
            }
            let hasUncategorized = visibleParents.contains { item in
                item.section == nil || isOrphan(item)
            }
            let sectionKeys: [String]
            if namedKeys.isEmpty {
                sectionKeys = hasUncategorized ? [listDetailUncategorizedKey] : []
            } else {
                sectionKeys = namedKeys + (hasUncategorized ? [listDetailUncategorizedKey] : [])
            }

            for key in sectionKeys {
                let isOthers = (key == listDetailUncategorizedKey)
                let entries: [Item]
                if isOthers {
                    entries = visibleParents.filter { item in
                        item.section == nil || isOrphan(item)
                    }
                } else {
                    entries = visibleParents.filter { $0.section == key }
                }
                if isOthers && entries.isEmpty { continue }

                let sectionId: SectionKey = .section(key: key)
                snapshot.appendSections([sectionId])

                if dropTarget == .before(key) {
                    snapshot.appendItems([.sectionDropPlaceholder(id: Self.sectionDropPlaceholderId)], toSection: sectionId)
                }

                let showHeader: Bool
                if isOthers {
                    showHeader = !list.sections.isEmpty
                } else {
                    showHeader = true
                }
                if showHeader {
                    snapshot.appendItems([.sectionHeader(key: key)], toSection: sectionId)
                }

                let userExpanded = showHeader ? parent.prefs.sectionExpanded(key, in: parent.listId) : true
                // Collapse only the section being dragged. Every other
                // section honors the user's expand-state preference so the
                // surrounding context stays visible during a reorder.
                let isDragging = (key == draggingKey)
                let expanded = userExpanded && !isDragging
                if expanded {
                    let sorted = parent.applySort(entries)
                    let flat = parent.flattenWithChildren(sorted)
                    snapshot.appendItems(flat.map { .item(id: $0.item.id, indent: $0.indent) }, toSection: sectionId)
                }
            }

            if dropTarget == .afterLast,
               let lastSection = snapshot.sectionIdentifiers.last {
                snapshot.appendItems([.sectionDropPlaceholder(id: Self.sectionDropPlaceholderId)], toSection: lastSection)
            }

            // Diffable won't re-run a cell's registration when its identifier
            // is unchanged, so a row whose *content* changed (e.g. a chevron
            // rotating after a collapse toggle) needs an explicit reconfigure.
            if !reconfigure.isEmpty {
                let present = Set(snapshot.itemIdentifiers)
                snapshot.reconfigureItems(reconfigure.filter { present.contains($0) })
            }

            dataSource.apply(snapshot, animatingDifferences: animated)
        }

        private func itemDropCueIndent(for target: ItemDropTarget?) -> Int {
            guard let target else { return 0 }
            switch target {
            case .nestInto(let id):
                return min(depthOf(id) + 1, 2)
            case .gap(let gap):
                return gap.indent
            }
        }

        // MARK: Item drop cue overlay

        private func setItemDropTarget(_ target: ItemDropTarget?, in collectionView: UICollectionView) {
            itemDropTarget = target
            updateItemDropCue(for: target, in: collectionView)
        }

        private func clearItemDropTarget() {
            itemDropTarget = nil
            hideItemDropCue()
            clearItemDropTransforms()
        }

        private func updateItemDropCue(for target: ItemDropTarget?, in collectionView: UICollectionView) {
            guard let target, let parent = parent else {
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
                let leading = ListsDensity.rowPadX + CGFloat(gap.indent) * 24
                let available = max(0, collectionView.bounds.width - leading - ListsDensity.rowPadX)
                // Hug the dragged line's width; fall back to full width and
                // never exceed the room left at this indent.
                let width = min(draggingContentWidth ?? available, available)
                let frame = CGRect(
                    x: leading,
                    y: gy + (Self.itemDropCueSpace - Self.itemDropCueHeight) / 2,
                    width: width,
                    height: Self.itemDropCueHeight
                )
                applyItemDropTransforms(after: gy, in: collectionView)
                showItemDropCue(frame: frame, color: color, style: .placement, in: collectionView)
            }
        }

        private func showItemDropCue(frame: CGRect,
                                     color: UIColor,
                                     style: ItemDropCueStyle,
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

            cue.layer.cornerRadius = style == .nesting ? 8 : 7
            cue.backgroundColor = color.withAlphaComponent(style == .nesting ? 0.16 : 0.18)
            cue.layer.borderColor = color.withAlphaComponent(style == .nesting ? 0.35 : 0.75).cgColor
            cue.layer.borderWidth = style == .nesting ? 0 : 1
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
            let shift = Self.itemDropCueSpace
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

        private func gapY(for gap: GapPosition, in collectionView: UICollectionView) -> CGFloat? {
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

        /// Natural (content-hugging) width of a row's content, stripped of
        /// the leading indent padding and trailing padding so it can be
        /// re-anchored at whatever indent the user drags to.
        private func measuredContentWidth(forCellAt indexPath: IndexPath,
                                          sourceIndent: Int,
                                          in collectionView: UICollectionView) -> CGFloat? {
            guard let cell = collectionView.cellForItem(at: indexPath) else { return nil }
            let fit = cell.contentView.systemLayoutSizeFitting(
                UIView.layoutFittingCompressedSize,
                withHorizontalFittingPriority: .fittingSizeLevel,
                verticalFittingPriority: .fittingSizeLevel
            )
            let leadingPad = ListsDensity.rowPadX + CGFloat(sourceIndent) * 24
            let content = fit.width - leadingPad - ListsDensity.rowPadX
            return content > 0 ? content : nil
        }

        private func frameForItem(_ id: UUID, in collectionView: UICollectionView) -> CGRect? {
            for row in dataSource.snapshot().itemIdentifiers {
                guard case .item(let rowId, let indent) = row, rowId == id,
                      let indexPath = dataSource.indexPath(for: .item(id: rowId, indent: indent)) else {
                    continue
                }
                return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
            }
            return nil
        }

        private func frameForSectionHeader(_ key: String, in collectionView: UICollectionView) -> CGRect? {
            let row = RowItem.sectionHeader(key: key)
            guard let indexPath = dataSource.indexPath(for: row) else { return nil }
            return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
        }

        private func lastItemFrame(inSection key: String, in collectionView: UICollectionView) -> CGRect? {
            itemFrames(inSection: key, in: collectionView).last
        }

        private func itemFrames(inSection key: String, in collectionView: UICollectionView) -> [CGRect] {
            let sectionId = SectionKey.section(key: key)
            // Exclude the item being dragged and its descendants — their rows
            // still occupy space in the snapshot during a drag, so counting
            // them would place the end-of-section gap below the held item's
            // vacated slot (mirrors the filter in `resolvedItemDropTarget`).
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

        // MARK: Drag

        func collectionView(_ collectionView: UICollectionView,
                            itemsForBeginning session: UIDragSession,
                            at indexPath: IndexPath) -> [UIDragItem] {
            guard let row = dataSource.itemIdentifier(for: indexPath) else { return [] }
            // Disable drag while the user is in select-reminders mode — the
            // row tap already does double duty as selection, and dragging
            // would steal taps and feel chaotic.
            if parent?.inSelectMode == true { return [] }
            switch row {
            case .item(let id, let indent):
                let drag = UIDragItem(itemProvider: NSItemProvider())
                drag.localObject = row
                draggingItemId = id
                draggingContentWidth = measuredContentWidth(forCellAt: indexPath,
                                                            sourceIndent: indent,
                                                            in: collectionView)
                clearItemDropTarget()
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
                if self.draggingSectionKey != nil || self.sectionDropTarget != nil {
                    self.draggingSectionKey = nil
                    self.sectionDropTarget = nil
                    self.applySnapshot(animated: true)
                }
                self.draggingItemId = nil
                self.draggingContentWidth = nil
                self.clearItemDropTarget()
            }
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
            draggingItemId = nil
            draggingContentWidth = nil
            clearSectionDropTarget()
            clearItemDropTarget()
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnter session: UIDropSession) {
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

        private func setSectionDropTarget(_ target: SectionDropTarget?) {
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
                                               sourceKey: String) -> SectionDropTarget? {
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
                    let target: SectionDropTarget = .before(key)
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

        private func endSectionDropTarget(sourceKey: String) -> SectionDropTarget? {
            let snap = dataSource.snapshot()
            let hasOthers = snap.sectionIdentifiers.contains {
                if case .section(let key) = $0 { return key == listDetailUncategorizedKey }
                return false
            }
            let target: SectionDropTarget = hasOthers ? .before(listDetailUncategorizedKey) : .afterLast
            return isNoOpSectionDrop(target, sourceKey: sourceKey) ? nil : target
        }

        private func isNoOpSectionDrop(_ target: SectionDropTarget, sourceKey: String) -> Bool {
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

        private func computeDropProposal(collectionView: UICollectionView, session: UIDropSession, destination: IndexPath?) -> UICollectionViewDropProposal {
            guard let dragItem = session.localDragSession?.items.first,
                  let sourceRow = dragItem.localObject as? RowItem else {
                return UICollectionViewDropProposal(operation: .cancel)
            }

            if case .item(let id, _) = sourceRow {
                let target = resolvedItemDropTarget(collectionView: collectionView, session: session, sourceId: id)
                setItemDropTarget(target, in: collectionView)
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

        private func resolvedItemDropTarget(collectionView: UICollectionView,
                                            session: UIDropSession,
                                            sourceId: UUID) -> ItemDropTarget? {
            let touch = session.location(in: collectionView)
            let snap = dataSource.snapshot()
            let sourceSubtreeDepth = subtreeDepthOf(sourceId)

            // Build per-section visible rows + header frames.
            struct SectionLayout {
                let key: String
                var headerFrame: CGRect?
                var rows: [VisibleRow] = []
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
                        layout.rows.append(VisibleRow(id: id, depth: indent, frame: attrs.frame))
                    default:
                        break
                    }
                }
                layout.rows.sort { $0.frame.minY < $1.frame.minY }
                sections.append(layout)
            }

            // 1. Touch INSIDE a row's frame: center band nests; halves are gaps.
            for section in sections {
                for (i, row) in section.rows.enumerated() {
                    guard row.frame.insetBy(dx: 0, dy: -2).contains(touch) else { continue }
                    let relY = (touch.y - row.frame.minY) / max(row.frame.height, 1)
                    if relY >= 0.36, relY <= 0.64,
                       canNestItem(sourceId, inside: row.id) {
                        return .nestInto(row.id)
                    }
                    if relY < 0.5 {
                        let above = i > 0 ? section.rows[i - 1] : nil
                        let indent = chooseIndent(touchX: touch.x,
                                                  rowAboveDepth: above?.depth,
                                                  rowBelowDepth: row.depth,
                                                  sourceSubtreeDepth: sourceSubtreeDepth)
                        return .gap(GapPosition(sectionKey: section.key,
                                                beforeRowId: row.id,
                                                indent: indent))
                    }
                    let below = i + 1 < section.rows.count ? section.rows[i + 1] : nil
                    let indent = chooseIndent(touchX: touch.x,
                                              rowAboveDepth: row.depth,
                                              rowBelowDepth: below?.depth,
                                              sourceSubtreeDepth: sourceSubtreeDepth)
                    return .gap(GapPosition(sectionKey: section.key,
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
                    return .gap(GapPosition(sectionKey: prev.key,
                                            beforeRowId: nil,
                                            indent: 0))
                }
                return .gap(GapPosition(sectionKey: section.key,
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
                    return collectionView.contentSize.height
                }()
                guard touch.y >= headerFrame.maxY, touch.y < nextHeaderMinY else { continue }

                if section.rows.isEmpty {
                    return .gap(GapPosition(sectionKey: section.key,
                                            beforeRowId: nil,
                                            indent: 0))
                }

                // Gap above first row.
                if touch.y < section.rows[0].frame.minY {
                    return .gap(GapPosition(sectionKey: section.key,
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
                    return .gap(GapPosition(sectionKey: section.key,
                                            beforeRowId: below?.id,
                                            indent: indent))
                }
            }

            return nil
        }

        /// Maps a horizontal touch position to a target indent.
        ///
        /// Each indent level is one 24pt step from the section's leading
        /// content edge (`ListsDensity.rowPadX`). The chosen depth is then
        /// clamped by:
        ///   - `rowAbove.depth + 1` — can't be deeper than one child of the
        ///     row above (with the hard cap at 2 = grandchild).
        ///   - `2 - sourceSubtreeDepth` — if the dragged item has its own
        ///     children, it can't sit at a depth that would push them past
        ///     the cap.
        ///   - `rowBelow.depth` from below — dropping shallower than the row
        ///     immediately after the gap would split that row's parent's
        ///     children (geometrically the dropped item would render at the
        ///     END of the parent's children, not between them).
        private func chooseIndent(touchX: CGFloat,
                                  rowAboveDepth: Int?,
                                  rowBelowDepth: Int?,
                                  sourceSubtreeDepth: Int) -> Int {
            guard let rowAboveDepth = rowAboveDepth else { return 0 }
            let raw = Int(floor((touchX - ListsDensity.rowPadX) / 24))
            let maxByAbove = min(rowAboveDepth + 1, 2)
            let maxBySubtree = max(0, 2 - sourceSubtreeDepth)
            let maxIndent = min(maxByAbove, maxBySubtree)
            let minIndent = max(0, min(rowBelowDepth ?? 0, maxIndent))
            return max(minIndent, min(raw, maxIndent))
        }

        private func canNestItem(_ sourceId: UUID, inside targetId: UUID) -> Bool {
            targetId != sourceId
                && !isDescendant(targetId, of: sourceId)
                && (depthOf(targetId) + subtreeDepthOf(sourceId) + 1) <= 2
        }

        /// Resolves the new parentId for a gap drop based on the chosen indent
        /// and the row immediately above. Returns nil for top-level drops
        /// (`gap.indent == 0`) or when there's no row above.
        ///
        /// Algorithm: walk up the row-above's ancestor chain by
        /// `(rowAbove.depth + 1 - gap.indent)` levels. That puts the dropped
        /// item at exactly `gap.indent`.
        private func computeNewParentId(for gap: GapPosition, sourceId: UUID) -> UUID? {
            guard gap.indent > 0, let parent = parent else { return nil }
            let sectionId = SectionKey.section(key: gap.sectionKey)
            let rows = dataSource.snapshot().itemIdentifiers(inSection: sectionId)
            var rowAbove: (id: UUID, depth: Int)? = nil
            for row in rows {
                if case .item(let id, _) = row, let stop = gap.beforeRowId, id == stop {
                    break
                }
                if case .item(let id, let indent) = row,
                   id != sourceId, !isDescendant(id, of: sourceId) {
                    rowAbove = (id, indent)
                }
            }
            guard let above = rowAbove else { return nil }
            let stepsUp = above.depth + 1 - gap.indent
            if stepsUp <= 0 { return above.id }
            var current: UUID? = above.id
            for _ in 0..<stepsUp {
                guard let id = current,
                      let item = parent.store.items.first(where: { $0.id == id }) else {
                    return nil
                }
                current = item.parentId
            }
            return current
        }

        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
            guard let item = coordinator.items.first,
                  let sourceRow = item.dragItem.localObject as? RowItem else { return }

            // Clear the drag-collapse flag now so the next snapshot rebuild
            // (triggered by the async store update) re-emits the section's
            // items.
            let pendingSectionDropTarget = sectionDropTarget
            let pendingItemDropTarget = itemDropTarget
            draggingSectionKey = nil
            draggingItemId = nil
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
                // the weird mid-state where UIKit slots the section preview
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

        private func lastIndexPath(in snap: NSDiffableDataSourceSnapshot<SectionKey, RowItem>) -> IndexPath? {
            let lastSec = snap.sectionIdentifiers.count - 1
            guard lastSec >= 0 else { return nil }
            let count = snap.itemIdentifiers(inSection: snap.sectionIdentifiers[lastSec]).count
            guard count > 0 else { return nil }
            return IndexPath(item: count - 1, section: lastSec)
        }

        // MARK: Context menu

        func collectionView(_ collectionView: UICollectionView,
                            contextMenuConfigurationForItemAt indexPath: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
            guard let row = dataSource.itemIdentifier(for: indexPath),
                  case .item(let id, _) = row,
                  let parent = parent,
                  let item = parent.store.items.first(where: { $0.id == id }) else {
                return nil
            }
            // Suppress context menu while in select-reminders mode — the tap
            // is doing selection, so a competing long-press menu would
            // confuse the gesture model.
            if parent.inSelectMode { return nil }
            return UIContextMenuConfiguration(identifier: id.uuidString as NSCopying, previewProvider: nil) { [weak self] _ in
                let flagAction = UIAction(
                    title: item.flagged ? "Unflag" : "Flag",
                    image: UIImage(systemName: item.flagged ? "flag.slash" : "flag")
                ) { _ in
                    Task { @MainActor in
                        var copy = item
                        copy.flagged.toggle()
                        try? await self?.parent?.store.update(copy)
                    }
                }
                let deleteAction = UIAction(
                    title: "Delete",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.parent?.onSoftDeleteItem(id)
                }
                return UIMenu(children: [flagAction, deleteAction])
            }
        }

        // MARK: Swipe actions

        func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let row = dataSource.itemIdentifier(for: indexPath),
                  let parent = parent else { return nil }
            switch row {
            case .item(let id, _):
                guard let item = parent.store.items.first(where: { $0.id == id }) else { return nil }
                let store = parent.store
                let onShowItemDetail = parent.onShowItemDetail
                let onSoftDeleteItem = parent.onSoftDeleteItem

                let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                    onSoftDeleteItem(id)
                    completion(true)
                }
                delete.image = UIImage(systemName: "trash")
                delete.backgroundColor = .systemRed

                let flag = UIContextualAction(
                    style: .normal,
                    title: item.flagged ? "Unflag" : "Flag"
                ) { _, _, completion in
                    Task { @MainActor in
                        var copy = item
                        copy.flagged.toggle()
                        try? await store.update(copy)
                    }
                    completion(true)
                }
                flag.image = UIImage(systemName: item.flagged ? "flag.slash" : "flag")
                flag.backgroundColor = .systemOrange

                let details = UIContextualAction(style: .normal, title: "Details") { _, _, completion in
                    onShowItemDetail(item)
                    completion(true)
                }
                details.image = UIImage(systemName: "info.circle")
                details.backgroundColor = .systemGray

                let config = UISwipeActionsConfiguration(actions: [delete, flag, details])
                config.performsFirstActionWithFullSwipe = true
                return config
            case .sectionHeader(let key):
                guard key != listDetailUncategorizedKey, let sid = UUID(uuidString: key) else { return nil }
                let name = parent.sectionDisplayName(for: key) ?? "section"
                let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                    parent.onPromptDeleteSection(sid, name)
                    completion(true)
                }
                delete.image = UIImage(systemName: "trash")
                return UISwipeActionsConfiguration(actions: [delete])
            case .subListChild(let id):
                let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                    parent.onSoftDeleteSubList(id)
                    completion(true)
                }
                delete.image = UIImage(systemName: "trash")
                return UISwipeActionsConfiguration(actions: [delete])
            default:
                return nil
            }
        }

        /// Leading-edge swipe (swipe right) — Indent / Outdent on item rows.
        /// Mirrors `ItemRow.swift`'s leading swipe logic.
        func leadingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let row = dataSource.itemIdentifier(for: indexPath),
                  case .item(let id, _) = row,
                  let parent = parent,
                  let item = parent.store.items.first(where: { $0.id == id }) else { return nil }
            let store = parent.store

            if item.parentId != nil {
                let outdent = UIContextualAction(style: .normal, title: "Outdent") { _, _, completion in
                    Task { @MainActor in
                        var copy = item
                        copy.parentId = nil
                        try? await store.update(copy)
                    }
                    completion(true)
                }
                outdent.image = UIImage(systemName: "decrease.indent")
                outdent.backgroundColor = UIColor(ListsTokens.accent)
                let config = UISwipeActionsConfiguration(actions: [outdent])
                config.performsFirstActionWithFullSwipe = false
                return config
            }

            // Find the previous sibling row in the same UICollectionView section.
            let snap = dataSource.snapshot()
            guard indexPath.section < snap.sectionIdentifiers.count else { return nil }
            let sectionId = snap.sectionIdentifiers[indexPath.section]
            let rowsInSection = snap.itemIdentifiers(inSection: sectionId)
            let prevIdx = indexPath.item - 1
            guard prevIdx >= 0, prevIdx < rowsInSection.count else { return nil }
            guard case .item(let prevId, _) = rowsInSection[prevIdx] else { return nil }
            let prevItem = parent.store.items.first(where: { $0.id == prevId })
            let previousSiblingParentId = prevItem?.parentId

            let indent = UIContextualAction(style: .normal, title: "Indent") { _, _, completion in
                Task { @MainActor in
                    var copy = item
                    copy.parentId = previousSiblingParentId ?? prevId
                    try? await store.update(copy)
                }
                completion(true)
            }
            indent.image = UIImage(systemName: "increase.indent")
            indent.backgroundColor = UIColor(ListsTokens.accent)
            let config = UISwipeActionsConfiguration(actions: [indent])
            config.performsFirstActionWithFullSwipe = false
            return config
        }

        // MARK: Reorder operations

        private func currentIndexPath(forItemId id: UUID) -> IndexPath? {
            let snap = dataSource.snapshot()
            for row in snap.itemIdentifiers {
                if case .item(let rid, let indent) = row, rid == id {
                    return dataSource.indexPath(for: .item(id: rid, indent: indent))
                }
            }
            return nil
        }

        /// Returns true if `candidateId` is a descendant of `ancestorId`
        /// in the current item tree. Used for cycle prevention on nest.
        private func isDescendant(_ candidateId: UUID, of ancestorId: UUID) -> Bool {
            guard let parent = parent else { return false }
            var current: UUID? = candidateId
            var visited: Set<UUID> = []
            while let c = current {
                if c == ancestorId { return true }
                if visited.contains(c) { return false } // safety against existing cycles
                visited.insert(c)
                current = parent.store.items.first(where: { $0.id == c })?.parentId
            }
            return false
        }

        /// Depth of `id` in the parent chain. 0 = top-level item, 1 = sub-item,
        /// 2 = grand-child. Used to enforce the renderer's 3-level cap when
        /// proposing a nest drop.
        private func depthOf(_ id: UUID) -> Int {
            guard let parent = parent else { return 0 }
            var depth = 0
            var current: UUID? = id
            var visited: Set<UUID> = []
            while let c = current, !visited.contains(c) {
                visited.insert(c)
                guard let item = parent.store.items.first(where: { $0.id == c }),
                      let pid = item.parentId else { break }
                depth += 1
                current = pid
            }
            return depth
        }

        /// Deepest descendant offset under `id` — 0 for leaf, 1 if item has
        /// children, 2 if it has grandchildren. Combined with `depthOf(target)`
        /// when deciding whether a nest would push the dragged subtree past
        /// the renderer's 3-level cap.
        private func subtreeDepthOf(_ id: UUID) -> Int {
            guard let parent = parent else { return 0 }
            var maxDepth = 0
            // Iterative BFS — items aren't deep in practice, but avoid blowing
            // the stack if the tree got corrupted.
            var queue: [(UUID, Int)] = [(id, 0)]
            var visited: Set<UUID> = []
            while !queue.isEmpty {
                let (current, depth) = queue.removeFirst()
                if visited.contains(current) { continue }
                visited.insert(current)
                let children = parent.store.items
                    .filter { $0.parentId == current && $0.deletedAt == nil }
                for child in children {
                    let childDepth = depth + 1
                    if childDepth > maxDepth { maxDepth = childDepth }
                    queue.append((child.id, childDepth))
                }
            }
            return maxDepth
        }

        @discardableResult
        private func performItemReorder(itemId: UUID, dropTarget: ItemDropTarget) -> Bool {
            guard let parent = parent else { return false }
            let snap = dataSource.snapshot()
            guard let item = parent.store.items.first(where: { $0.id == itemId }) else { return false }

            enum InsertPlacement {
                case start
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

            let insertIdx: Int
            switch placement {
            case .start:
                insertIdx = 0
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
            // Apply synchronously so the data source reflects the new state
            // before `coordinator.drop(_:toItemAt:)` animates the preview —
            // otherwise UIKit animates to a stale indexPath and the move
            // visually snaps back.
            if changed {
                store.applyUpdateSync(copy)
            }
            if prefs.sort(for: listId) != .manual {
                prefs.setSort(.manual, for: listId)
            }
            if !prefs.sectionExpanded(sectionKey, in: listId) {
                prefs.setSectionExpanded(true, sectionId: sectionKey, in: listId)
            }
            store.applyReorderItemsSync(in: listId, flatOrderedIds: fullOrder)
            applySnapshot(animated: false)
            return true
        }

        @discardableResult
        private func performSectionReorder(sourceKey: String,
                                           to target: SectionDropTarget?,
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

            // No-op moves (same position) — skip the store write and signal
            // a rejected drop so the preview animates back to its original
            // cell rather than appearing to "snap into" the destination.
            if rebuilt == namedKeys { return false }

            let orderedIds = rebuilt.compactMap { UUID(uuidString: $0) }
            let listId = parent.listId
            let store = parent.store
            // Apply synchronously so the data source reflects the new
            // ordering before `coordinator.drop(_:toItemAt:)` animates.
            store.applyReorderSectionsSync(in: listId, orderedIds: orderedIds)
            applySnapshot(animated: false)
            return true
        }

        private func isPastEnd(_ dest: IndexPath,
                               in snap: NSDiffableDataSourceSnapshot<SectionKey, RowItem>) -> Bool {
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
                                             in snap: NSDiffableDataSourceSnapshot<SectionKey, RowItem>) -> Bool {
            let lastSectionIdx = snap.sectionIdentifiers.count - 1
            guard lastSectionIdx >= 0, dest.section == lastSectionIdx else { return false }
            let count = snap.itemIdentifiers(inSection: snap.sectionIdentifiers[lastSectionIdx]).count
            return count > 0 && dest.item == count - 1
        }
    }
}

// MARK: - Helpers used by Coordinator

extension ListDetailCollectionView {
    func sectionDisplayName(for key: String) -> String? {
        if key == listDetailUncategorizedKey {
            return (list?.sections.isEmpty == false) ? "Others" : nil
        }
        return list?.sections.first { $0.id.uuidString == key }?.name
    }

    func isOverdue(_ item: Item) -> Bool {
        guard let due = item.due else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    func applySort(_ items: [Item]) -> [Item] {
        items.sortedBy(prefs.sort(for: listId), direction: prefs.sortDirection(for: listId))
    }

    func flattenWithChildren(_ parents: [Item]) -> [(item: Item, indent: Int)] {
        var out: [(Item, Int)] = []
        let showCompleted = prefs.showCompleted(for: listId)
        let lingering = lingeringIds
        // Child predicate mirrors `visibleParents` — keep just-completed
        // items visible during the linger window so they fade out instead
        // of vanishing instantly.
        let isChildVisible: (Item) -> Bool = { item in
            item.deletedAt == nil
                && (showCompleted || !item.isComplete || lingering.contains(item.id))
        }
        for top in parents {
            out.append((top, 0))
            // A collapsed item hides its whole subtree from the flat list.
            guard prefs.itemExpanded(top.id.uuidString, in: listId) else { continue }
            let children = store.items
                .filter { $0.parentId == top.id && isChildVisible($0) }
                .sorted { $0.sortIndex < $1.sortIndex }
            for c in children {
                out.append((c, 1))
                guard prefs.itemExpanded(c.id.uuidString, in: listId) else { continue }
                let gchildren = store.items
                    .filter { $0.parentId == c.id && isChildVisible($0) }
                    .sorted { $0.sortIndex < $1.sortIndex }
                for g in gchildren {
                    out.append((g, 2))
                }
            }
        }
        return out
    }
}

// MARK: - Cell content (SwiftUI hosted inside UICollectionViewListCell)

private struct CVSubListsHeaderRow: View {
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Sub-Lists")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { onToggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ListsDensity.rowPadX)
        .padding(.vertical, 2)
    }
}

private struct CVSubListChildRow: View {
    let child: ItemList
    let openItemCount: Int
    let onOpen: () -> Void

    var body: some View {
        // Plain Button + manual chevron (no NavigationLink): the system
        // disclosure indicator that NavigationLink draws sits at a different
        // trailing inset than the Sub-Lists header chevron above, so we
        // route the tap programmatically and draw a matching chevron at
        // trailing = rowPadX to make the two share an x-position.
        Button(action: onOpen) {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: child.icon,
                    hue: ListsTokens.listColor(child.color),
                    shape: .circle
                )
                Text(child.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(openItemCount)")
                    .font(ListsTypography.mono)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ListsDensity.rowPadX)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CVSectionDropPlaceholder: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(height: height)
            .contentShape(Rectangle())
    }
}

private struct CVSectionHeaderRow: View {
    let sectionKey: String
    let displayName: String
    let isOthers: Bool
    let expanded: Bool
    let showTopDivider: Bool
    let listColor: Color
    let onToggleExpanded: () -> Void
    let onCommitRename: (String) -> Void

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        let color: Color = isOthers ? .secondary : .primary
        VStack(alignment: .leading, spacing: 8) {
            if showTopDivider {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 1)
                    .padding(.horizontal, ListsDensity.rowPadX)
            }
            HStack(spacing: 8) {
                Group {
                    if isRenaming {
                        TextField(displayName, text: $renameText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(color)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($renameFocused)
                            .onSubmit(commit)
                            .onChange(of: renameFocused) { _, focused in
                                if !focused { commit() }
                            }
                            .accessibilityIdentifier("list.section.\(sectionKey).title")
                    } else {
                        Text(displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(color)
                            .contentShape(Rectangle())
                            .onTapGesture { beginRename() }
                            .accessibilityIdentifier("list.section.\(sectionKey).title")
                    }
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { onToggleExpanded() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("list.section.\(sectionKey).chevron")
            }
            .padding(.horizontal, ListsDensity.rowPadX)
        }
        .padding(.vertical, 2)
    }

    private func beginRename() {
        renameText = isOthers ? "" : displayName
        isRenaming = true
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commit() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onCommitRename(trimmed) }
        isRenaming = false
    }
}
