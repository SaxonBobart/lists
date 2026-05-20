import SwiftUI
import UIKit

/// UIKit-backed renderer for the body of `TodayView` and `SmartListScreen`.
/// Shares the same cell visuals + swipe / context-menu vocabulary as
/// `ListDetailCollectionView` so the whole app feels consistent.
///
/// Smart-list views are read-mostly — date-grouped buckets and per-list
/// All-view groupings come from the parent SwiftUI screen as a `[SmartListGroup]`
/// array. This renderer just builds the snapshot and supplies swipe / context-
/// menu interactions per item.
///
/// Drag-to-reorder is intentionally NOT enabled here (the order is derived
/// from `due` date / list position / filter rules, not from user-set
/// `sortIndex`). Items are still draggable for swipe actions and the
/// context menu.
struct SmartListCollectionView: UIViewRepresentable {
    let store: ItemStore
    var prefs: ListViewPreferences
    let groups: [SmartListGroup]
    let onToggleItem: (Item) -> Void
    let onIncrementHabit: (Item) -> Void
    let onSoftDeleteItem: (UUID) -> Void
    let onShowItemDetail: (Item) -> Void

    func makeUIView(context: Context) -> UICollectionView {
        let layout = makeLayout(context: context)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.delegate = context.coordinator
        cv.alwaysBounceVertical = true
        cv.contentInsetAdjustmentBehavior = .automatic
        // Smart-list views derive their order from date/list/filter rules,
        // not user-set sortIndex — explicit reorder isn't meaningful here.
        // Disable drag-interaction to keep long-press routed straight to the
        // context menu instead of a half-initialised drag session.
        cv.dragInteractionEnabled = false

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

// MARK: - Public data model

struct SmartListGroup: Identifiable, Hashable {
    let id: String
    let rows: [SmartListRow]
}

enum SmartListRow: Hashable {
    case listHeader(listId: String, name: String, color: ItemList.ListColor)
    case sectionTitle(id: String, text: String, isOverdue: Bool)
    case item(id: UUID, indent: Int)
}

// MARK: - Coordinator

extension SmartListCollectionView {
    final class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: SmartListCollectionView?
        var dataSource: UICollectionViewDiffableDataSource<SmartListGroup, SmartListRow>!
        weak var collectionView: UICollectionView?

        func setupDataSource(for cv: UICollectionView) {
            self.collectionView = cv

            let listHeaderReg = makeListHeaderReg()
            let sectionTitleReg = makeSectionTitleReg()
            let itemReg = makeItemReg()

            dataSource = UICollectionViewDiffableDataSource<SmartListGroup, SmartListRow>(collectionView: cv) {
                cv, indexPath, row in
                switch row {
                case .listHeader:
                    return cv.dequeueConfiguredReusableCell(using: listHeaderReg, for: indexPath, item: row)
                case .sectionTitle:
                    return cv.dequeueConfiguredReusableCell(using: sectionTitleReg, for: indexPath, item: row)
                case .item:
                    return cv.dequeueConfiguredReusableCell(using: itemReg, for: indexPath, item: row)
                }
            }
        }

        private func makeListHeaderReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, SmartListRow> {
            UICollectionView.CellRegistration { cell, _, row in
                guard case .listHeader(_, let name, let color) = row else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    SLListHeaderRow(name: name, color: ListsTokens.listColor(color))
                }
                .margins(.all, 0)
            }
        }

        private func makeSectionTitleReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, SmartListRow> {
            UICollectionView.CellRegistration { cell, indexPath, row in
                guard case .sectionTitle(_, let text, let isOverdue) = row else { return }
                let isFirstRow = (indexPath == IndexPath(item: 0, section: 0))
                cell.contentConfiguration = UIHostingConfiguration {
                    SLSectionTitleRow(text: text, isOverdue: isOverdue, showTopDivider: !isFirstRow)
                }
                .margins(.all, 0)
            }
        }

        private func makeItemReg() -> UICollectionView.CellRegistration<UICollectionViewListCell, SmartListRow> {
            UICollectionView.CellRegistration { [weak self] cell, _, row in
                guard case .item(let id, let indent) = row,
                      let parent = self?.parent,
                      let item = parent.store.items.first(where: { $0.id == id }) else { return }
                let store = parent.store
                let onToggleItem = parent.onToggleItem
                let onIncrementHabit = parent.onIncrementHabit
                cell.contentConfiguration = UIHostingConfiguration {
                    ItemRow(
                        item: item,
                        isOverdue: Self.isOverdue(item),
                        store: store,
                        onToggle: { onToggleItem(item) },
                        onIncrementHabit: { onIncrementHabit(item) },
                        indent: indent,
                        previousSiblingId: nil,
                        previousSiblingParentId: nil,
                        showSubItemIndicator: false,
                        inSelectMode: false,
                        isSelected: false,
                        onSelectToggle: {}
                    )
                }
                .margins(.all, 0)
            }
        }

        // MARK: Snapshot

        func applySnapshot(animated: Bool) {
            guard let parent = parent else { return }
            var snapshot = NSDiffableDataSourceSnapshot<SmartListGroup, SmartListRow>()
            for group in parent.groups {
                snapshot.appendSections([group])
                snapshot.appendItems(group.rows, toSection: group)
            }
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: animated)
        }

        // MARK: Swipe actions (item rows only)

        func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let row = dataSource.itemIdentifier(for: indexPath),
                  case .item(let id, _) = row,
                  let parent = parent,
                  let item = parent.store.items.first(where: { $0.id == id }) else { return nil }
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
        }

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

            // Walk backward through the current section to find the previous
            // item-row in the same list (so an Indent target is valid).
            let snap = dataSource.snapshot()
            guard indexPath.section < snap.sectionIdentifiers.count else { return nil }
            let sectionId = snap.sectionIdentifiers[indexPath.section]
            let rowsInSection = snap.itemIdentifiers(inSection: sectionId)
            var prevItemId: UUID?
            for prevIdx in stride(from: indexPath.item - 1, through: 0, by: -1) {
                if case .item(let pid, _) = rowsInSection[prevIdx] {
                    prevItemId = pid
                    break
                }
            }
            guard let prevId = prevItemId,
                  let prevItem = parent.store.items.first(where: { $0.id == prevId }),
                  prevItem.listId == item.listId else { return nil }
            let previousSiblingParentId = prevItem.parentId

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

        // MARK: Context menu (item rows only)

        func collectionView(_ collectionView: UICollectionView,
                            contextMenuConfigurationForItemAt indexPath: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
            guard let row = dataSource.itemIdentifier(for: indexPath),
                  case .item(let id, _) = row,
                  let parent = parent,
                  let item = parent.store.items.first(where: { $0.id == id }) else { return nil }
            return UIContextMenuConfiguration(identifier: id.uuidString as NSCopying, previewProvider: nil) { [weak self] _ in
                let flag = UIAction(
                    title: item.flagged ? "Unflag" : "Flag",
                    image: UIImage(systemName: item.flagged ? "flag.slash" : "flag")
                ) { _ in
                    Task { @MainActor in
                        var copy = item
                        copy.flagged.toggle()
                        try? await self?.parent?.store.update(copy)
                    }
                }
                let delete = UIAction(
                    title: "Delete",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.parent?.onSoftDeleteItem(id)
                }
                return UIMenu(children: [flag, delete])
            }
        }

        // MARK: Helpers

        private static func isOverdue(_ item: Item) -> Bool {
            guard let due = item.due else { return false }
            return due < Calendar.current.startOfDay(for: .now)
        }
    }
}

// MARK: - SwiftUI cells

private struct SLListHeaderRow: View {
    let name: String
    let color: Color
    var body: some View {
        Text(name)
            .font(.title2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, ListsDensity.rowPadX)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

private struct SLSectionTitleRow: View {
    let text: String
    let isOverdue: Bool
    let showTopDivider: Bool

    var body: some View {
        let color: Color = isOverdue ? .red : .primary
        VStack(alignment: .leading, spacing: 8) {
            if showTopDivider {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 1)
                    .padding(.horizontal, ListsDensity.rowPadX)
            }
            Text(text)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, ListsDensity.rowPadX)
        }
        .padding(.vertical, 2)
    }
}
