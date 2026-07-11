import UIKit

extension ListDetailCollectionView.Coordinator {
    func applySnapshot(animated: Bool, reconfigure: [ListDetailCollectionView.RowItem] = []) {
        guard !isResigningEditingCell else { return }
        guard let parent, let list = parent.list else { return }

        typealias SectionKey = ListDetailCollectionView.SectionKey
        typealias RowItem = ListDetailCollectionView.RowItem

        var snapshot = NSDiffableDataSourceSnapshot<SectionKey, RowItem>()

        if parent.moveSession.isActive {
            snapshot.appendSections([.moveDestination])
            snapshot.appendItems([.moveNone], toSection: .moveDestination)
        }

        let draggingKey = draggingSectionKey
        let dropTarget = sectionDropTarget

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

        let showCompleted = parent.prefs.showCompleted(for: parent.listId)
        let showPastEvents = parent.prefs.showPastEvents(for: parent.listId)
        let itemTypePolicy = ItemTypePolicy(habitsEnabled: parent.habitsPluginEnabled)
        let now = Date.now
        let calendar = Calendar.current
        let visibleParents = parent.store.items.filter { item in
            item.listId == parent.listId
                && item.deletedAt == nil
                && item.parentId == nil
                && item.isAvailable(in: itemTypePolicy)
                && !parent.moveSession.isMoving(item.id)
                && (showCompleted || !item.isComplete(at: now) || parent.lingeringIds.contains(item.id))
                && (showPastEvents || !item.isRolledOffPastEvent(now: now, calendar: calendar))
        }
        let namedKeys = list.sections
            .sorted { $0.position < $1.position }
            .map(\.id.uuidString)
        let namedKeysSet = Set(namedKeys)
        let isOrphan: (Item) -> Bool = { item in
            guard let section = item.section else { return false }
            return !namedKeysSet.contains(section)
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
                snapshot.appendItems(
                    [.sectionDropPlaceholder(id: Self.sectionDropPlaceholderId)],
                    toSection: sectionId
                )
            }

            let showHeader = isOthers ? !list.sections.isEmpty : true
            if showHeader {
                let headerRow: RowItem = (!isOthers && key == parent.editingSectionKey)
                    ? .editingSectionHeader(key: key)
                    : .sectionHeader(key: key)
                snapshot.appendItems([headerRow], toSection: sectionId)
            }

            let expanded = parent.sectionExpandedForRendering(
                key,
                showHeader: showHeader,
                draggingKey: draggingKey
            )
            if expanded {
                let sorted = parent.applySort(entries)
                let hiddenItemId = parent.moveSession.movingItemId
                    ?? (dragSourceHidden ? draggingItemId : nil)
                let flat = parent.flattenWithChildren(
                    sorted,
                    draggingItemId: hiddenItemId,
                    forceExpanded: parent.isDestinationModeActive
                )
                let editingId = parent.editingItemId
                snapshot.appendItems(flat.map { entry in
                    entry.item.id == editingId && itemTypePolicy.allowsInlineEditing(entry.item)
                        ? .editingItem(id: entry.item.id, indent: entry.indent)
                        : .item(id: entry.item.id, indent: entry.indent)
                }, toSection: sectionId)
            }
        }

        if dropTarget == .afterLast,
           let lastSection = snapshot.sectionIdentifiers.last {
            snapshot.appendItems(
                [.sectionDropPlaceholder(id: Self.sectionDropPlaceholderId)],
                toSection: lastSection
            )
        }

        let orderedSectionKeys = snapshot.sectionIdentifiers.compactMap { section -> String? in
            guard case .section(let key) = section else { return nil }
            return key
        }
        let hasSubLists = snapshot.sectionIdentifiers.contains(.subLists)
        let nextSectionHeaderState = Dictionary(uniqueKeysWithValues: orderedSectionKeys.map { key in
            (
                key,
                ListDetailCollectionView.SectionHeaderRenderState(
                    displayName: parent.sectionDisplayName(for: key) ?? "",
                    showsTopDivider: ListDetailCollectionView.sectionHeaderShowsTopDivider(
                        key: key,
                        orderedSectionKeys: orderedSectionKeys,
                        hasSubLists: hasSubLists
                    )
                )
            )
        })
        let changedSectionHeaders: [RowItem] = snapshot.itemIdentifiers.compactMap { row in
            let key: String
            switch row {
            case .sectionHeader(let value), .editingSectionHeader(let value): key = value
            default: return nil
            }
            guard let previous = renderedSectionHeaderState[key],
                  previous != nextSectionHeaderState[key] else { return nil }
            return row
        }
        renderedSectionHeaderState = nextSectionHeaderState

        let present = Set(snapshot.itemIdentifiers)
        let previousItems = Set(dataSource.snapshot().itemIdentifiers)
        let dragInFlight = draggingItemId != nil || draggingSectionKey != nil
        let lingerRows: [RowItem] = dragInFlight ? [] : snapshot.itemIdentifiers.filter {
            if case .item(let id, _) = $0 { return parent.lingeringIds.contains(id) }
            return false
        }

        var changedContentRows: [RowItem] = []
        if !dragInFlight {
            let parentsWithChildren = Set(
                parent.store.items.compactMap { $0.deletedAt == nil ? $0.parentId : nil }
            )
            var nextRendered: [RowItem: ListDetailCollectionView.ItemRenderState] = [:]
            for row in snapshot.itemIdentifiers {
                guard case .item(let id, let indent) = row,
                      let item = parent.store.item(id) else { continue }
                let state = ListDetailCollectionView.ItemRenderState(
                    item: item,
                    indent: indent,
                    isOverdue: parent.isOverdue(item),
                    inSelectMode: parent.inSelectMode,
                    inMoveMode: parent.isDestinationModeActive,
                    isSelected: parent.selection.contains(id),
                    isExpanded: parent.isDestinationModeActive
                        || parent.prefs.itemExpanded(id.uuidString, in: parent.listId),
                    hasChildren: parentsWithChildren.contains(id)
                )
                nextRendered[row] = state
                if previousItems.contains(row),
                   renderedItemState[row] != state,
                   !lingerRows.contains(row) {
                    changedContentRows.append(row)
                }
            }
            renderedItemState = nextRendered
        }

        let reloadRows = lingerRows + changedContentRows
        let requestedReconfigureRows = reconfigure + changedSectionHeaders
        let reconfigureRows = requestedReconfigureRows.reduce(into: [RowItem]()) { rows, row in
            guard present.contains(row),
                  !reloadRows.contains(row),
                  !rows.contains(row) else { return }
            rows.append(row)
        }
        if !reconfigureRows.isEmpty {
            snapshot.reconfigureItems(reconfigureRows)
        }
        if !reloadRows.isEmpty {
            snapshot.reloadItems(reloadRows)
        }

        let editingCellRemoved = previousItems.contains { row in
            if case .editingItem = row { return !present.contains(row) }
            return false
        }
        if editingCellRemoved {
            isResigningEditingCell = true
            collectionView?.endEditing(true)
            isResigningEditingCell = false
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }
}
