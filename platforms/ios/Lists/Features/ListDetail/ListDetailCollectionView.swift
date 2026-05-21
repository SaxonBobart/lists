import SwiftUI
import UIKit

/// UIKit-backed renderer for the body of `ListDetailView`. Replaces
/// SwiftUI's `List` so we get hierarchical drag-and-drop that SwiftUI's
/// flat `.onMove` can't express:
///
/// - Item drags are scoped to within the item's section. Drop hints
///   never fall between section boundaries.
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
        private var sectionDropTarget: SectionDropTarget?
        private var itemDropTarget: ItemDropTarget?
        private var itemDropCueView: UIView?
        private var itemDropShiftedCells: [UICollectionViewCell] = []

        private enum SectionDropTarget: Hashable {
            case before(String)
            case afterLast
        }

        private enum ItemDropTarget: Hashable {
            case beforeItem(UUID)
            case afterItem(UUID)
            case afterGroup(groupId: UUID, anchorId: UUID)
            case insideItem(UUID)
            case startOfSection(String)
            case endOfSection(String)
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
                    CVSubListsHeaderRow(expanded: expanded) {
                        prefs.setSubListsExpanded(!expanded, for: listId)
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
                        onToggleExpanded: {
                            prefs.setSectionExpanded(!expanded, sectionId: key, in: listId)
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
                        onSelectToggle: { onSelectToggle(id) }
                    )
                }
                .margins(.all, 0)
                cell.accessibilityIdentifier = "list.item.\(item.id.uuidString)"
            }
        }

        // MARK: Snapshot

        func applySnapshot(animated: Bool) {
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

            dataSource.apply(snapshot, animatingDifferences: animated)
        }

        private func itemDropCueIndent(for target: ItemDropTarget?) -> Int {
            guard let target else { return 0 }
            switch target {
            case .beforeItem(let id), .afterItem(let id):
                return depthOf(id)
            case .insideItem(let id):
                return min(depthOf(id) + 1, 2)
            case .afterGroup, .startOfSection, .endOfSection:
                return 0
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
            case .insideItem(let targetId):
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
            case .beforeItem, .afterItem, .afterGroup, .startOfSection, .endOfSection:
                guard let gapY = itemDropGapY(for: target, in: collectionView) else {
                    hideItemDropCue()
                    return
                }
                let indent = itemDropCueIndent(for: target)
                let leading = ListsDensity.rowPadX + CGFloat(indent) * 24
                let width = max(0, collectionView.bounds.width - leading - ListsDensity.rowPadX)
                let frame = CGRect(
                    x: leading,
                    y: gapY + (Self.itemDropCueSpace - Self.itemDropCueHeight) / 2,
                    width: width,
                    height: Self.itemDropCueHeight
                )
                applyItemDropTransforms(after: gapY, in: collectionView)
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

        private func itemDropGapY(for target: ItemDropTarget, in collectionView: UICollectionView) -> CGFloat? {
            switch target {
            case .beforeItem(let id):
                return frameForItem(id, in: collectionView)?.minY
            case .afterItem(let id):
                return frameForLastItem(inSubtreeOf: id, in: collectionView)?.maxY
            case .afterGroup(let groupId, _):
                return frameForLastItem(inSubtreeOf: groupId, in: collectionView)?.maxY
            case .insideItem:
                return nil
            case .startOfSection(let key):
                if let header = frameForSectionHeader(key, in: collectionView) {
                    return header.maxY
                }
                return firstItemFrame(inSection: key, in: collectionView)?.minY
                    ?? sectionFallbackY(key, in: collectionView)
            case .endOfSection(let key):
                return lastItemFrame(inSection: key, in: collectionView)?.maxY
                    ?? frameForSectionHeader(key, in: collectionView)?.maxY
                    ?? sectionFallbackY(key, in: collectionView)
            }
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

        private func frameForLastItem(inSubtreeOf id: UUID, in collectionView: UICollectionView) -> CGRect? {
            var lastFrame: CGRect?
            for row in dataSource.snapshot().itemIdentifiers {
                guard case .item(let rowId, let indent) = row,
                      (rowId == id || isDescendant(rowId, of: id)),
                      let indexPath = dataSource.indexPath(for: .item(id: rowId, indent: indent)),
                      let frame = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame else {
                    continue
                }
                if lastFrame == nil || frame.maxY > (lastFrame?.maxY ?? 0) {
                    lastFrame = frame
                }
            }
            return lastFrame
        }

        private func frameForSectionHeader(_ key: String, in collectionView: UICollectionView) -> CGRect? {
            let row = RowItem.sectionHeader(key: key)
            guard let indexPath = dataSource.indexPath(for: row) else { return nil }
            return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
        }

        private func firstItemFrame(inSection key: String, in collectionView: UICollectionView) -> CGRect? {
            itemFrames(inSection: key, in: collectionView).first
        }

        private func lastItemFrame(inSection key: String, in collectionView: UICollectionView) -> CGRect? {
            itemFrames(inSection: key, in: collectionView).last
        }

        private func itemFrames(inSection key: String, in collectionView: UICollectionView) -> [CGRect] {
            let sectionId = SectionKey.section(key: key)
            return dataSource.snapshot()
                .itemIdentifiers(inSection: sectionId)
                .compactMap { row -> CGRect? in
                    guard case .item(let id, let indent) = row,
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
            case .item(let id, _):
                let drag = UIDragItem(itemProvider: NSItemProvider())
                drag.localObject = row
                draggingItemId = id
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
                self.clearItemDropTarget()
            }
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
            draggingItemId = nil
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
                guard let target else {
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

            var itemFrames: [(id: UUID, indent: Int, frame: CGRect)] = []
            var headerFrames: [(key: String, frame: CGRect)] = []
            var sectionKeys: [String] = []

            for sectionId in snap.sectionIdentifiers {
                guard case .section(let sectionKey) = sectionId else { continue }
                sectionKeys.append(sectionKey)
                for row in snap.itemIdentifiers(inSection: sectionId) {
                    guard let indexPath = dataSource.indexPath(for: row),
                          let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
                        continue
                    }
                    switch row {
                    case .sectionHeader:
                        headerFrames.append((sectionKey, attributes.frame))
                    case .item(let targetId, let indent)
                        where targetId != sourceId && !isDescendant(targetId, of: sourceId):
                        itemFrames.append((targetId, indent, attributes.frame))
                    default:
                        break
                    }
                }
            }
            itemFrames.sort { $0.frame.minY < $1.frame.minY }
            headerFrames.sort { $0.frame.minY < $1.frame.minY }

            for (targetId, indent, frame) in itemFrames {
                let relativeY = (touch.y - frame.minY) / max(frame.height, 1)
                guard frame.insetBy(dx: 0, dy: -2).contains(touch) else { continue }
                if relativeY > 0.36, relativeY < 0.64 {
                    return canNestItem(sourceId, inside: targetId) ? .insideItem(targetId) : nil
                }
                if indent > 0,
                   relativeY > 0.64,
                   isInParentLane(touch, for: frame, indent: indent) {
                    return .afterGroup(groupId: topLevelAncestorId(for: targetId), anchorId: targetId)
                }
                return relativeY <= 0.36 ? .beforeItem(targetId) : .afterItem(targetId)
            }

            for (targetId, indent, frame) in itemFrames {
                let belowRowNestBand = CGRect(
                    x: nestingLaneMinX(for: frame, indent: indent),
                    y: frame.maxY,
                    width: frame.maxX - nestingLaneMinX(for: frame, indent: indent),
                    height: 12
                )
                if belowRowNestBand.contains(touch) {
                    if indent > 0 {
                        return .afterItem(targetId)
                    }
                    if canNestItem(sourceId, inside: targetId) {
                        return .insideItem(targetId)
                    }
                }
                let parentLaneBand = CGRect(
                    x: frame.minX,
                    y: frame.maxY,
                    width: max(0, nestingLaneMinX(for: frame, indent: indent) - frame.minX),
                    height: 28
                )
                if indent > 0, parentLaneBand.contains(touch) {
                    return .afterGroup(groupId: topLevelAncestorId(for: targetId), anchorId: targetId)
                }
            }

            if case .insideItem(let stickyTarget) = itemDropTarget,
               let (_, indent, frame) = itemFrames.first(where: { $0.id == stickyTarget }),
               frame.insetBy(dx: 0, dy: -6).contains(touch) {
                if indent > 0, isInParentLane(touch, for: frame, indent: indent) {
                    return .afterGroup(groupId: topLevelAncestorId(for: stickyTarget), anchorId: stickyTarget)
                }
                let relativeY = (touch.y - frame.minY) / max(frame.height, 1)
                guard relativeY > 0.28, relativeY < 1.05 else { return nil }
                return canNestItem(sourceId, inside: stickyTarget) ? .insideItem(stickyTarget) : nil
            }

            for (sectionKey, frame) in headerFrames {
                if frame.contains(touch) {
                    let relativeY = (touch.y - frame.minY) / max(frame.height, 1)
                    if relativeY < 0.45,
                       let index = sectionKeys.firstIndex(of: sectionKey),
                       index > 0 {
                        return .endOfSection(sectionKeys[index - 1])
                    }
                    return .startOfSection(sectionKey)
                }
            }

            for sectionId in snap.sectionIdentifiers {
                guard case .section(let sectionKey) = sectionId else { continue }
                let rows = snap.itemIdentifiers(inSection: sectionId)
                let sectionHeaderFrame = rows.compactMap { row -> CGRect? in
                    guard case .sectionHeader = row,
                          let indexPath = dataSource.indexPath(for: row) else { return nil }
                    return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
                }.first
                let sectionItems = rows.compactMap { row -> (UUID, CGRect)? in
                    guard case .item(let targetId, _) = row,
                          targetId != sourceId,
                          !isDescendant(targetId, of: sourceId),
                          let indexPath = dataSource.indexPath(for: row),
                          let frame = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame else {
                        return nil
                    }
                    return (targetId, frame)
                }.sorted { $0.1.minY < $1.1.minY }

                let nextHeaderMinY = headerFrames
                    .map(\.frame.minY)
                    .filter { $0 > (sectionHeaderFrame?.minY ?? -CGFloat.greatestFiniteMagnitude) }
                    .min() ?? collectionView.contentSize.height

                guard touch.y < nextHeaderMinY else { continue }

                if let headerFrame = sectionHeaderFrame,
                   sectionItems.isEmpty,
                   touch.y > headerFrame.maxY,
                   touch.y < nextHeaderMinY {
                    return .startOfSection(sectionKey)
                }

                guard let first = sectionItems.first else { continue }
                if let headerFrame = sectionHeaderFrame,
                   touch.y > headerFrame.maxY,
                   touch.y < first.1.minY {
                    return .beforeItem(first.0)
                }

                for index in sectionItems.indices {
                    let current = sectionItems[index]
                    let next = index + 1 < sectionItems.count ? sectionItems[index + 1] : nil
                    let lowerBound = current.1.maxY
                    let upperBound = next?.1.minY ?? nextHeaderMinY
                    if touch.y > lowerBound, touch.y < upperBound {
                        return next == nil ? .endOfSection(sectionKey) : .afterItem(current.0)
                    }
                }
            }

            return nil
        }

        private func canNestItem(_ sourceId: UUID, inside targetId: UUID) -> Bool {
            targetId != sourceId
                && !isDescendant(targetId, of: sourceId)
                && (depthOf(targetId) + subtreeDepthOf(sourceId) + 1) <= 2
        }

        private func nestingLaneMinX(for frame: CGRect, indent: Int) -> CGFloat {
            frame.minX + ListsDensity.rowPadX + CGFloat(indent) * 24 + 20
        }

        private func isInParentLane(_ point: CGPoint, for frame: CGRect, indent: Int) -> Bool {
            point.x < nestingLaneMinX(for: frame, indent: indent)
        }

        private func topLevelAncestorId(for id: UUID) -> UUID {
            guard let parent = parent else { return id }
            var current = parent.store.items.first(where: { $0.id == id })
            var top = id
            var visited: Set<UUID> = []

            while let item = current,
                  let parentId = item.parentId,
                  !visited.contains(parentId) {
                visited.insert(parentId)
                top = parentId
                current = parent.store.items.first(where: { $0.id == parentId })
            }

            return top
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
            case .insideItem(let targetId):
                guard canNestItem(itemId, inside: targetId),
                      let target = parent.store.items.first(where: { $0.id == targetId && $0.deletedAt == nil }) else {
                    return false
                }
                sectionKey = target.section ?? listDetailUncategorizedKey
                newParentId = target.id
                placement = .inside(target.id)
            case .beforeItem(let targetId), .afterItem(let targetId):
                guard targetId != itemId,
                      !isDescendant(targetId, of: itemId),
                      let target = parent.store.items.first(where: { $0.id == targetId && $0.deletedAt == nil }) else {
                    return false
                }
                sectionKey = target.section ?? listDetailUncategorizedKey
                newParentId = target.parentId
                placement = {
                    if case .beforeItem = dropTarget { return .before(target.id) }
                    return .after(target.id)
                }()
            case .afterGroup(let targetId, _):
                guard targetId != itemId,
                      !isDescendant(targetId, of: itemId),
                      let target = parent.store.items.first(where: { $0.id == targetId && $0.deletedAt == nil }) else {
                    return false
                }
                sectionKey = target.section ?? listDetailUncategorizedKey
                newParentId = target.parentId
                placement = .after(target.id)
            case .startOfSection(let key):
                sectionKey = key
                newParentId = nil
                placement = .start
            case .endOfSection(let key):
                sectionKey = key
                newParentId = nil
                placement = .end
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
            let children = store.items
                .filter { $0.parentId == top.id && isChildVisible($0) }
                .sorted { $0.sortIndex < $1.sortIndex }
            for c in children {
                out.append((c, 1))
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
                    .foregroundStyle(.primary)
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
