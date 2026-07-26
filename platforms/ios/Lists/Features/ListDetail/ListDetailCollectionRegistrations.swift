import SwiftUI
import UIKit

extension ListDetailCollectionView.Coordinator {
    private typealias SectionKey = ListDetailCollectionView.SectionKey
    private typealias RowItem = ListDetailCollectionView.RowItem

    func setupDataSource(for cv: UICollectionView) {
        collectionView = cv

        let subListsHeader = makeSubListsHeaderReg()
        let subListChild = makeSubListChildReg()
        let moveNone = makeMoveNoneReg()
        let sectionHeader = makeSectionHeaderReg()
        let sectionDropPlaceholder = makeSectionDropPlaceholderReg()
        let item = makeItemReg()
        let editingItem = makeEditingItemReg()

        dataSource = UICollectionViewDiffableDataSource<SectionKey, RowItem>(collectionView: cv) {
            cv, indexPath, row in
            switch row {
            case .moveNone:
                return cv.dequeueConfiguredReusableCell(using: moveNone, for: indexPath, item: row)
            case .subListsHeader:
                return cv.dequeueConfiguredReusableCell(using: subListsHeader, for: indexPath, item: row)
            case .subListChild:
                return cv.dequeueConfiguredReusableCell(using: subListChild, for: indexPath, item: row)
            case .sectionHeader, .editingSectionHeader:
                return cv.dequeueConfiguredReusableCell(using: sectionHeader, for: indexPath, item: row)
            case .sectionDropPlaceholder:
                return cv.dequeueConfiguredReusableCell(using: sectionDropPlaceholder, for: indexPath, item: row)
            case .item:
                return cv.dequeueConfiguredReusableCell(using: item, for: indexPath, item: row)
            case .editingItem:
                return cv.dequeueConfiguredReusableCell(using: editingItem, for: indexPath, item: row)
            }
        }
    }

    private func configureListCell(_ cell: UICollectionViewListCell) {
        cell.transform = .identity
        cell.preservesSuperviewLayoutMargins = false
        cell.directionalLayoutMargins = .zero
        cell.layoutMargins = .zero
        cell.contentView.preservesSuperviewLayoutMargins = false
        cell.contentView.directionalLayoutMargins = .zero
        cell.contentView.layoutMargins = .zero
        cell.backgroundConfiguration = .clear()
    }

    private func makeMoveNoneReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
        UICollectionView.CellRegistration { [weak self] cell, _, _ in
            self?.configureListCell(cell)
            guard let parent = self?.parent else { return }
            let listName = parent.list?.name ?? "List"
            let listColor = parent.listColor
            cell.contentConfiguration = UIHostingConfiguration {
                MoveNoneDestinationRow(listName: listName, listColor: listColor) {
                    parent.moveSession.commit(toList: parent.listId, parent: nil, store: parent.store)
                }
            }
            .margins(.all, 0)
            cell.accessibilityIdentifier = "move.destination.none"
        }
    }

    private func makeSubListsHeaderReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
        UICollectionView.CellRegistration { [weak self] cell, _, _ in
            self?.configureListCell(cell)
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
            self?.configureListCell(cell)
            guard case .subListChild(let id) = row,
                  let parent = self?.parent,
                  let child = parent.store.lists.first(where: { $0.id == id }) else { return }
            let count = parent.store.openItemCount(
                in: child.id,
                itemTypePolicy: ItemTypePolicy(habitsEnabled: parent.habitsPluginEnabled)
            )
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
            self?.configureListCell(cell)
            let key: String
            let startEditing: Bool
            switch row {
            case .sectionHeader(let k):        key = k; startEditing = false
            case .editingSectionHeader(let k): key = k; startEditing = true
            default: return
            }
            guard let parent = self?.parent else { return }
            let isOthers = (key == listDetailUncategorizedKey)
            let renderedState = self?.renderedSectionHeaderState[key]
            let displayName = renderedState?.displayName
                ?? parent.sectionDisplayName(for: key)
                ?? ""
            let listId = parent.listId
            let prefs = parent.prefs
            let userExpanded = prefs.sectionExpanded(key, in: listId)
            let isMoveMode = parent.moveSession.isActive
            let expanded = isMoveMode || userExpanded
            let showTopDivider = parent.presentation == .list
                && (renderedState?.showsTopDivider
                    ?? ListDetailCollectionView.sectionHeaderShowsTopDivider(
                        key: key,
                        orderedSectionKeys: parent.renderedSectionKeys,
                        hasSubLists: parent.store.lists.contains {
                            $0.parentId == parent.listId && $0.deletedAt == nil
                        }
                    ))
            let listColor = parent.listColor
            let isColumn = parent.presentation == .columns
            let onPromoteOthers = parent.onPromoteOthers
            let onRenameSection = parent.onRenameSection
            let onEndEditSection = parent.onEndEditSection
            cell.contentConfiguration = UIHostingConfiguration {
                CVSectionHeaderRow(
                    sectionKey: key,
                    displayName: displayName,
                    isOthers: isOthers,
                    expanded: expanded,
                    showTopDivider: showTopDivider,
                    listColor: listColor,
                    isColumn: isColumn,
                    startEditing: startEditing,
                    onToggleExpanded: { [weak self] in
                        guard !isMoveMode else { return }
                        prefs.setSectionExpanded(!userExpanded, sectionId: key, in: listId)
                        self?.applySnapshot(animated: true, reconfigure: [.sectionHeader(key: key)])
                    },
                    onCommitRename: { newName in
                        if isOthers {
                            onPromoteOthers(newName)
                        } else if let uuid = UUID(uuidString: key) {
                            onRenameSection(uuid, newName)
                        }
                    },
                    onEndEditing: { onEndEditSection() }
                )
            }
            .margins(.all, 0)
            cell.accessibilityIdentifier = "list.section.\(key)"
        }
    }

    private func makeSectionDropPlaceholderReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
        UICollectionView.CellRegistration { [weak self] cell, _, _ in
            self?.configureListCell(cell)
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
            self?.configureListCell(cell)
            guard case .item(let id, let indent) = row,
                  let parent = self?.parent,
                  let item = parent.store.item(id) else { return }
            let store = parent.store
            let inSelectMode = parent.inSelectMode
            let isSelected = parent.selection.contains(id)
            let onToggleItem = parent.onToggleItem
            let onIncrementHabit = parent.onIncrementHabit
            let onSelectToggle = parent.onSelectToggle
            let onShowItemDetail = parent.onShowItemDetail
            let onBeginInlineEdit = parent.onBeginInlineEdit
            let moveSession = parent.moveSession
            let documentLinkSession = parent.documentLinkSession
            let prefs = parent.prefs
            let listId = parent.listId
            let isExpanded = prefs.itemExpanded(id.uuidString, in: listId)
            let isMoveMode = moveSession.isActive
            let isLinkMode = documentLinkSession.isActive
            let isDestinationMode = isMoveMode || isLinkMode
            let canPickMoveTarget = isMoveMode && moveSession.canPickParent(id, in: store)
            let canPickLinkTarget = isLinkMode && documentLinkSession.canPick(item)
            cell.contentConfiguration = UIHostingConfiguration {
                ItemRow(
                    item: item,
                    isOverdue: parent.isOverdue(item),
                    store: store,
                    onToggle: { onToggleItem(item) },
                    onIncrementHabit: { onIncrementHabit(item) },
                    indent: indent,
                    showSubItemIndicator: false,
                    showMetadata: !isDestinationMode,
                    inSelectMode: inSelectMode,
                    isSelected: isSelected,
                    onSelectToggle: { onSelectToggle(id) },
                    showCollapseControl: !isDestinationMode,
                    isExpanded: isDestinationMode || isExpanded,
                    onToggleCollapse: { [weak self] in
                        prefs.setItemExpanded(!isExpanded, itemId: id.uuidString, in: listId)
                        self?.applySnapshot(animated: true, reconfigure: [.item(id: id, indent: indent)])
                    },
                    leadingPadding: ListDetailLayout.leadingEdge,
                    trailingPadding: ListDetailLayout.trailingEdge,
                    verticalPadding: parent.presentation == .columns
                        ? ListDetailLayout.columnRowPadY
                        : ListsDensity.rowPadY,
                    minimumHeight: parent.presentation == .columns ? 44 : nil,
                    onShowDetail: { _ in onShowItemDetail(item) },
                    onBeginInlineEdit: { onBeginInlineEdit($0) },
                    onPick: isDestinationMode ? { _ in
                        if canPickMoveTarget {
                            moveSession.commit(toList: listId, parent: id, store: store)
                        } else if canPickLinkTarget {
                            documentLinkSession.commit(to: item, store: store)
                        }
                    } : nil,
                    enablesSwipeActions: false
                )
                .disabled(isDestinationMode && !canPickMoveTarget && !canPickLinkTarget)
                .opacity(isDestinationMode && !canPickMoveTarget && !canPickLinkTarget ? 0.35 : 1)
            }
            .margins(.all, 0)
            cell.accessibilityIdentifier = "list.item.\(item.id.uuidString)"
        }
    }

    /// Cell hosting the inline editor (`InlineItemEditor`) for the one row
    /// in `editingItemId`. Mirrors `makeItemReg`'s lookups but swaps the
    /// static `ItemRow` for the live title/notes editor + keyboard toolbar.
    private func makeEditingItemReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, RowItem> {
        UICollectionView.CellRegistration { [weak self] cell, _, row in
            self?.configureListCell(cell)
            guard case .editingItem(let id, let indent) = row,
                  let parent = self?.parent,
                  let item = parent.store.item(id) else { return }
            let store = parent.store
            let listColor = parent.listColor
            let onEndInlineEdit = parent.onEndInlineEdit
            let onShowItemDetail = parent.onShowItemDetail
            let onBeginMove = parent.onBeginMove
            cell.contentConfiguration = UIHostingConfiguration {
                InlineItemEditor(
                    item: item,
                    store: store,
                    listColor: listColor,
                    indent: indent,
                    leadingPadding: ListDetailLayout.leadingEdge,
                    trailingPadding: ListDetailLayout.trailingEdge,
                    onEndEditing: { onEndInlineEdit($0) },
                    onShowDetail: { onShowItemDetail($0) },
                    onBeginMove: { onBeginMove($0) }
                )
            }
            .margins(.all, 0)
            cell.accessibilityIdentifier = "list.item.editing.\(id.uuidString)"
        }
    }
}
