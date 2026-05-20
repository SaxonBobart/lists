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
        cv.alwaysBounceVertical = true
        cv.contentInsetAdjustmentBehavior = .automatic

        context.coordinator.parent = self
        context.coordinator.setupDataSource(for: cv)
        context.coordinator.applySnapshot(animated: false)
        return cv
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
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
        var draggingSectionKey: String?

        // MARK: Data source setup

        func setupDataSource(for cv: UICollectionView) {
            self.collectionView = cv

            let subListsHeader = makeSubListsHeaderReg()
            let subListChild = makeSubListChildReg()
            let sectionHeader = makeSectionHeaderReg()
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
                case .item:
                    return cv.dequeueConfiguredReusableCell(using: item, for: indexPath, item: row)
                }
            }
        }

        private func makeSubListsHeaderReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, _, _ in
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
            }
        }

        private func makeSubListChildReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, _, row in
                guard case .subListChild(let id) = row,
                      let parent = self?.parent,
                      let child = parent.store.lists.first(where: { $0.id == id }) else { return }
                let count = parent.store.items.filter { $0.listId == child.id && !$0.done && $0.deletedAt == nil }.count
                cell.contentConfiguration = UIHostingConfiguration {
                    CVSubListChildRow(child: child, openItemCount: count)
                }
                .margins(.all, 0)
            }
        }

        private func makeSectionHeaderReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, indexPath, row in
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
            }
        }

        private func makeItemReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
            UICollectionView.CellRegistration { [weak self] cell, _, row in
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
            }
        }

        // MARK: Snapshot

        func applySnapshot(animated: Bool) {
            guard let parent = parent, let list = parent.list else { return }

            var snapshot = NSDiffableDataSourceSnapshot<SectionKey, RowItem>()

            // While a section drag is in flight, collapse ONLY the dragged
            // section's items — every other section keeps its body visible
            // so the user can see the surrounding context while reorganising.
            // The drop-validation logic in `dropSessionDidUpdate` snaps drops
            // over visible items to the nearest section boundary.
            let draggingKey = draggingSectionKey

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

            // Force cells to reconfigure so capture-only state (selection,
            // inSelectMode) refreshes on parent re-renders too.
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: animated)
        }

        // MARK: Drag

        func collectionView(_ collectionView: UICollectionView,
                            itemsForBeginning session: UIDragSession,
                            at indexPath: IndexPath) -> [UIDragItem] {
            guard let row = dataSource.itemIdentifier(for: indexPath) else { return [] }
            switch row {
            case .item:
                let drag = UIDragItem(itemProvider: NSItemProvider())
                drag.localObject = row
                return [drag]
            case .sectionHeader(let key) where key != listDetailUncategorizedKey:
                let drag = UIDragItem(itemProvider: NSItemProvider())
                drag.localObject = row
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
                if self.draggingSectionKey != nil {
                    self.draggingSectionKey = nil
                    self.applySnapshot(animated: true)
                }
            }
        }

        // MARK: Drop validation

        func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
            session.localDragSession != nil
        }

        func collectionView(_ collectionView: UICollectionView,
                            dropSessionDidUpdate session: UIDropSession,
                            withDestinationIndexPath destination: IndexPath?) -> UICollectionViewDropProposal {
            guard let dragItem = session.localDragSession?.items.first,
                  let sourceRow = dragItem.localObject as? RowItem else {
                return UICollectionViewDropProposal(operation: .cancel)
            }

            // No specific destination = user's finger is below the last row
            // (or otherwise outside any cell). For section drags this means
            // "move to the very end"; item drags need a destination so we
            // cancel.
            guard let dest = destination else {
                if case .sectionHeader = sourceRow {
                    return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
                }
                return UICollectionViewDropProposal(operation: .cancel)
            }

            let snapshot = dataSource.snapshot()
            guard dest.section < snapshot.sectionIdentifiers.count else {
                if case .sectionHeader = sourceRow {
                    return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
                }
                return UICollectionViewDropProposal(operation: .cancel)
            }

            switch sourceRow {
            case .item(let id, _):
                let destRow = dataSource.itemIdentifier(for: dest)

                // Drop on another item: either nest (cursor near cell midline)
                // or insert as a sibling. Reject if the target is the dragged
                // item itself or any of its descendants (cycle prevention).
                // Cap nest at depth 2 — the renderer only emits 3 levels
                // (parent → sub → grand) so a 4th level would visually vanish.
                if case .item(let targetId, _) = destRow {
                    if targetId == id || isDescendant(targetId, of: id) {
                        return UICollectionViewDropProposal(operation: .cancel)
                    }
                    let canNest = depthOf(targetId) < 2
                    if canNest, let cell = collectionView.cellForItem(at: dest) {
                        let touch = session.location(in: collectionView)
                        let relative = (touch.y - cell.frame.minY) / max(cell.frame.height, 1)
                        if relative > 0.25 && relative < 0.75 {
                            return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
                        }
                    }
                    return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
                }

                // Drop on a section header (any section): move to the top of
                // that section as a top-level item.
                if case .sectionHeader = destRow {
                    return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
                }

                // Drop on Sub-Lists header / sub-list child: forbidden.
                return UICollectionViewDropProposal(operation: .cancel)

            case .sectionHeader(let sourceKey):
                // With single-section collapse, other sections remain
                // expanded during a section drag — we still need to accept
                // (or reject) every position the user's finger lands on.
                //
                // Accepted positions:
                // 1. On another named section header — insert before it.
                // 2. On the Others header — move to the last named position.
                // 3. On any item row — snap to that row's section boundary
                //    so the user can drop "anywhere in section Y" and have
                //    it mean "insert before section Y".
                // 4. Past the very last row in the last section — "move to
                //    end". This is what makes drag-to-very-bottom work even
                //    without an Others bucket below.
                // 5. ON the very last row of the last section. UIKit clamps
                //    `destinationIndexPath` to the last cell when the user
                //    drags past the bottom edge, so without this branch the
                //    drag-to-end is silently rejected.
                let destRow = dataSource.itemIdentifier(for: dest)

                // Rejection: dropping onto the dragged section's own header
                // would be a no-op. Show forbidden so the indicator isn't
                // misleading.
                if case .sectionHeader(let destKey) = destRow, destKey == sourceKey {
                    return UICollectionViewDropProposal(operation: .forbidden)
                }
                // Rejection: dropping onto the Sub-Lists area never reorders
                // a section.
                if case .subListsHeader = destRow {
                    return UICollectionViewDropProposal(operation: .forbidden)
                }
                if case .subListChild = destRow {
                    return UICollectionViewDropProposal(operation: .forbidden)
                }

                // All other interior positions (.sectionHeader, .item) are
                // accepted. `performSectionReorder` snaps item destinations
                // to the containing section's header position.
                if case .sectionHeader = destRow {
                    return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
                }
                if case .item = destRow {
                    return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
                }
                if isPastEnd(dest, in: snapshot) || isLastCellOfLastSection(dest, in: snapshot) {
                    return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
                }
                return UICollectionViewDropProposal(operation: .forbidden)

            default:
                return UICollectionViewDropProposal(operation: .cancel)
            }
        }

        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
            guard let item = coordinator.items.first,
                  let sourceRow = item.dragItem.localObject as? RowItem else { return }

            // Clear the drag-collapse flag now so the next snapshot rebuild
            // (triggered by the async store update) re-emits the section's
            // items.
            draggingSectionKey = nil

            let destination = coordinator.destinationIndexPath
            let nesting = (coordinator.proposal.intent == .insertIntoDestinationIndexPath)
            switch sourceRow {
            case .item(let id, _):
                guard let dest = destination else { return }
                let moved = performItemReorder(itemId: id, to: dest, nesting: nesting)
                let finalTarget: IndexPath = moved
                    ? dest
                    : (currentIndexPath(forItemId: id) ?? dest)
                coordinator.drop(item.dragItem, toItemAt: finalTarget)
            case .sectionHeader(let key):
                let moved = performSectionReorder(sourceKey: key, to: destination)
                let snap = dataSource.snapshot()
                let finalTarget: IndexPath
                if moved {
                    finalTarget = destination ?? lastIndexPath(in: snap) ?? IndexPath(item: 0, section: 0)
                } else {
                    // Drop was rejected — animate the preview back to the
                    // section's own original position so the user sees a
                    // "snap back" instead of UIKit slotting the preview
                    // into the cell the finger happened to be over.
                    finalTarget = dataSource.indexPath(for: .sectionHeader(key: key))
                        ?? IndexPath(item: 0, section: 0)
                }
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

        @discardableResult
        private func performItemReorder(itemId: UUID, to dest: IndexPath, nesting: Bool) -> Bool {
            guard let parent = parent else { return false }
            let snap = dataSource.snapshot()
            guard dest.section < snap.sectionIdentifiers.count else { return false }
            let sectionId = snap.sectionIdentifiers[dest.section]
            guard case .section(let sectionKey) = sectionId else { return false }
            guard let item = parent.store.items.first(where: { $0.id == itemId }) else { return false }

            let newItemSection: String? = (sectionKey == listDetailUncategorizedKey) ? nil : sectionKey
            let destRow = dataSource.itemIdentifier(for: dest)

            // Step 1: figure out the new parentId + section for the dragged
            // item.
            var copy = item
            var changed = false

            // Cap nest at depth 2 (mirrors the proposal logic so a stray
            // .insertInto intent can't sneak past the renderer's 3-level cap).
            let depthOK: Bool = {
                guard nesting, case .item(let targetId, _) = destRow else { return true }
                return depthOf(targetId) < 2
            }()

            if nesting, depthOK, case .item(let targetId, _) = destRow {
                guard targetId != itemId, !isDescendant(targetId, of: itemId) else { return false }
                guard let target = parent.store.items.first(where: { $0.id == targetId }) else { return false }
                if copy.parentId != targetId {
                    copy.parentId = targetId
                    changed = true
                }
                if copy.section != target.section {
                    copy.section = target.section
                    changed = true
                }
            } else {
                if copy.section != newItemSection {
                    copy.section = newItemSection
                    changed = true
                }
                if copy.parentId != nil {
                    copy.parentId = nil
                    changed = true
                }
            }

            // Step 2: compute the new flat order in the destination section.
            let sectionRows = snap.itemIdentifiers(inSection: sectionId)
            var sectionItemIds: [UUID] = []
            var headerCountBeforeDest = 0
            for (i, row) in sectionRows.enumerated() {
                switch row {
                case .item(let rid, _) where rid != itemId:
                    sectionItemIds.append(rid)
                case .item:
                    break
                case .sectionHeader:
                    if i < dest.item { headerCountBeforeDest += 1 }
                default:
                    break
                }
            }
            let insertIdx: Int
            if nesting, case .item(let targetId, _) = destRow,
               let targetIdxInSection = sectionItemIds.firstIndex(of: targetId) {
                // Place dragged item right after target's existing
                // children. Walk forward while items remain children of
                // target (by checking store, since `copy` is what we want
                // to write but other items keep their existing parentId).
                var afterIdx = targetIdxInSection + 1
                while afterIdx < sectionItemIds.count,
                      let cand = parent.store.items.first(where: { $0.id == sectionItemIds[afterIdx] }),
                      isDescendant(cand.id, of: targetId) {
                    afterIdx += 1
                }
                insertIdx = afterIdx
            } else {
                insertIdx = max(0, min(dest.item - headerCountBeforeDest, sectionItemIds.count))
            }
            sectionItemIds.insert(itemId, at: insertIdx)

            // Combine with the rest of the list to make a full flat order.
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

            let listId = parent.listId
            let store = parent.store
            let prefs = parent.prefs
            Task { @MainActor in
                if changed {
                    try? await store.update(copy)
                }
                if prefs.sort(for: listId) != .manual {
                    prefs.setSort(.manual, for: listId)
                }
                try? await store.reorderItems(in: listId, flatOrderedIds: fullOrder)
            }
            return true
        }

        @discardableResult
        private func performSectionReorder(sourceKey: String, to dest: IndexPath?) -> Bool {
            guard let parent = parent, let list = parent.list else { return false }
            let snap = dataSource.snapshot()
            let namedKeys = list.sections
                .sorted { $0.position < $1.position }
                .map(\.id.uuidString)
            guard let oldIdx = namedKeys.firstIndex(of: sourceKey) else { return false }

            var rebuilt = namedKeys
            rebuilt.remove(at: oldIdx)

            // When the user's finger lands on an item row in another section,
            // resolve that to the section's header — dropping "in section Y"
            // means "insert source before section Y."
            let effectiveDestKey: String? = {
                guard let dest = dest else { return nil }
                let destRow = dataSource.itemIdentifier(for: dest)
                if case .sectionHeader(let k) = destRow { return k }
                if case .item = destRow,
                   dest.section < snap.sectionIdentifiers.count,
                   case .section(let k) = snap.sectionIdentifiers[dest.section] {
                    return k
                }
                return nil
            }()

            if let destKey = effectiveDestKey,
               destKey != listDetailUncategorizedKey,
               destKey != sourceKey,
               let targetIdx = namedKeys.firstIndex(of: destKey) {
                let adjusted = targetIdx > oldIdx ? targetIdx - 1 : targetIdx
                rebuilt.insert(sourceKey, at: max(0, min(adjusted, rebuilt.count)))
            } else if effectiveDestKey == listDetailUncategorizedKey {
                rebuilt.append(sourceKey)
            } else if let dest = dest,
                      isPastEnd(dest, in: snap) || isLastCellOfLastSection(dest, in: snap) {
                rebuilt.append(sourceKey)
            } else if dest == nil {
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
            Task { @MainActor in
                try? await store.reorderSections(in: listId, orderedIds: orderedIds)
            }
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
        for top in parents {
            out.append((top, 0))
            let children = store.items
                .filter { $0.parentId == top.id && $0.deletedAt == nil && (showCompleted || !$0.isComplete) }
                .sorted { $0.sortIndex < $1.sortIndex }
            for c in children {
                out.append((c, 1))
                let gchildren = store.items
                    .filter { $0.parentId == c.id && $0.deletedAt == nil && (showCompleted || !$0.isComplete) }
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

    var body: some View {
        NavigationLink(value: child) {
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, ListsDensity.rowPadX)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    } else {
                        Text(displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(color)
                            .contentShape(Rectangle())
                            .onTapGesture { beginRename() }
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
