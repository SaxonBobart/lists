import SwiftUI
import UIKit

/// UIKit-backed renderer for the body of `TodayView` and `SmartListScreen`.
/// Shares the same cell visuals plus trailing swipe/context-menu vocabulary
/// as `ListDetailCollectionView` so the whole app feels consistent.
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
/// Plain `UICollectionViewController` host so the enclosing
/// `UINavigationController` tracks our scroll view (large-title collapse +
/// liquid-glass scroll edge). SwiftUI doesn't auto-detect scroll views buried
/// inside a `UIViewControllerRepresentable`, so we hand the collection view to
/// the pushed hosting controller explicitly. Mirror of
/// `ListDetailCollectionViewController`.
final class SmartListCollectionViewController: UICollectionViewController {
    private var didAssociateScrollView = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        associateContentScrollViewIfNeeded()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        associateContentScrollViewIfNeeded()
    }

    private func associateContentScrollViewIfNeeded() {
        guard !didAssociateScrollView, let collectionView else { return }
        var node: UIViewController? = self
        while let current = node {
            if current.parent is UINavigationController {
                current.setContentScrollView(collectionView)
                didAssociateScrollView = true
                return
            }
            node = current.parent
        }
    }
}

struct SmartListCollectionView: UIViewControllerRepresentable {
    let store: ItemStore
    let moveSession: ItemMoveSession
    let documentLinkSession: DocumentLinkSession
    var prefs: ListViewPreferences
    let groups: [SmartListGroup]
    let onToggleItem: (Item) -> Void
    let onIncrementHabit: (Item) -> Void
    let onSoftDeleteItem: (UUID) -> Void
    let onMutationFailure: (String) -> Void
    let onShowItemDetail: (Item) -> Void
    var bottomContentInset: CGFloat = 0

    func makeUIViewController(context: Context) -> SmartListCollectionViewController {
        let layout = makeLayout(context: context)
        let vc = SmartListCollectionViewController(collectionViewLayout: layout)
        let cv = vc.collectionView!
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
        context.coordinator.applyContentInsets(to: cv)
        context.coordinator.applySnapshot(animated: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: SmartListCollectionViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyContentInsets(to: uiViewController.collectionView)
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
    case recurrenceOccurrence(itemId: UUID, occurrenceId: UUID)
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
            let recurrenceOccurrenceReg = makeRecurrenceOccurrenceReg()

            dataSource = UICollectionViewDiffableDataSource<SmartListGroup, SmartListRow>(collectionView: cv) {
                cv, indexPath, row in
                switch row {
                case .listHeader:
                    return cv.dequeueConfiguredReusableCell(using: listHeaderReg, for: indexPath, item: row)
                case .sectionTitle:
                    return cv.dequeueConfiguredReusableCell(using: sectionTitleReg, for: indexPath, item: row)
                case .item:
                    return cv.dequeueConfiguredReusableCell(using: itemReg, for: indexPath, item: row)
                case .recurrenceOccurrence:
                    return cv.dequeueConfiguredReusableCell(
                        using: recurrenceOccurrenceReg,
                        for: indexPath,
                        item: row
                    )
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
                      let item = parent.store.item(id) else { return }
                let store = parent.store
                let onToggleItem = parent.onToggleItem
                let onIncrementHabit = parent.onIncrementHabit
                let onShowItemDetail = parent.onShowItemDetail
                let isLinkMode = parent.documentLinkSession.isActive
                let canPickLinkTarget = isLinkMode && parent.documentLinkSession.canPick(item)
                cell.contentConfiguration = UIHostingConfiguration {
                    ItemRow(
                        item: item,
                        isOverdue: Self.isOverdue(item),
                        store: store,
                        onToggle: { onToggleItem(item) },
                        onIncrementHabit: { onIncrementHabit(item) },
                        indent: indent,
                        showSubItemIndicator: false,
                        showMetadata: !isLinkMode,
                        inSelectMode: false,
                        isSelected: false,
                        onSelectToggle: {},
                        onShowDetail: { _ in onShowItemDetail(item) },
                        onPick: isLinkMode ? { _ in
                            if canPickLinkTarget {
                                parent.documentLinkSession.commit(to: item, store: store)
                            }
                        } : nil,
                        enablesSwipeActions: false,
                        isReadOnly: parent.moveSession.isActive
                    )
                    .disabled(isLinkMode && !canPickLinkTarget)
                    .opacity(isLinkMode && !canPickLinkTarget ? 0.35 : 1)
                }
                .margins(.all, 0)
            }
        }

        private func makeRecurrenceOccurrenceReg()
            -> UICollectionView.CellRegistration<UICollectionViewListCell, SmartListRow> {
            UICollectionView.CellRegistration { [weak self] cell, _, row in
                guard case .recurrenceOccurrence(let itemId, let occurrenceId) = row,
                      let parent = self?.parent,
                      let item = parent.store.item(itemId),
                      let occurrence = item.recurrenceOccurrences.first(where: {
                          $0.id == occurrenceId && $0.status == .completed
                      }) else { return }
                let store = parent.store
                cell.contentConfiguration = UIHostingConfiguration {
                    RecurrenceCompletedSmartListRow(
                        item: item,
                        occurrence: occurrence,
                        onMarkMissed: {
                            Task { @MainActor in
                                do {
                                    try await store.correctRecurrenceOccurrence(
                                        itemId,
                                        occurrenceId: occurrenceId,
                                        status: .missed,
                                        completedAt: nil
                                    )
                                } catch {
                                    parent.onMutationFailure(error.localizedDescription)
                                }
                            }
                        },
                        onOpen: { parent.onShowItemDetail(item) }
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

        func applyContentInsets(to collectionView: UICollectionView) {
            guard let parent else { return }
            collectionView.contentInset.bottom = parent.bottomContentInset
            collectionView.verticalScrollIndicatorInsets.bottom = parent.bottomContentInset
        }

        // MARK: Swipe actions (item rows only)

        func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let row = dataSource.itemIdentifier(for: indexPath),
                  case .item(let id, _) = row,
                  let parent = parent,
                  let item = parent.store.item(id) else { return nil }
            if parent.moveSession.isActive || parent.documentLinkSession.isActive { return nil }
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
                    do {
                        try await store.toggleFlagged(id)
                        completion(true)
                    } catch {
                        parent.onMutationFailure(error.localizedDescription)
                        completion(false)
                    }
                }
            }
            flag.image = UIImage(systemName: item.flagged ? "flag.slash" : "flag")
            flag.backgroundColor = .systemOrange

            // "Open" for document types; habits keep "Details" (classic ⓘ screen).
            let details = UIContextualAction(
                style: .normal,
                title: item.type.supportsInlineEditing ? "Open" : "Details"
            ) { _, _, completion in
                onShowItemDetail(item)
                completion(true)
            }
            details.image = UIImage(systemName: item.type.supportsInlineEditing ? "text.document" : "info.circle")
            details.backgroundColor = .systemGray

            let config = UISwipeActionsConfiguration(actions: [delete, flag, details])
            config.performsFirstActionWithFullSwipe = true
            return config
        }

        // MARK: Context menu (item rows only)

        func collectionView(_ collectionView: UICollectionView,
                            contextMenuConfigurationForItemAt indexPath: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
            guard let row = dataSource.itemIdentifier(for: indexPath),
                  case .item(let id, _) = row,
                  let parent = parent,
                  let item = parent.store.item(id) else { return nil }
            if parent.moveSession.isActive || parent.documentLinkSession.isActive { return nil }
            return UIContextMenuConfiguration(identifier: id.uuidString as NSCopying, previewProvider: nil) { [weak self] _ in
                let flag = UIAction(
                    title: item.flagged ? "Unflag" : "Flag",
                    image: UIImage(systemName: item.flagged ? "flag.slash" : "flag")
                ) { _ in
                    Task { @MainActor in
                        guard let parent = self?.parent else { return }
                        do {
                            try await parent.store.toggleFlagged(id)
                        } catch {
                            parent.onMutationFailure(error.localizedDescription)
                        }
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
            item.isOverdue()
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

private struct RecurrenceCompletedSmartListRow: View {
    let item: Item
    let occurrence: RecurrenceOccurrence
    let onMarkMissed: () -> Void
    let onOpen: () -> Void

    private var idStem: String {
        "recurrence.completed.\(item.id.uuidString.lowercased()).\(occurrence.id.uuidString.lowercased())"
    }

    var body: some View {
        HStack(spacing: ListsSpacing.s3) {
            Button(action: onMarkMissed) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(ListsTokens.accent)
                    .frame(width: 28, height: 28, alignment: .leading)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .padding(-8)
            .accessibilityLabel("Mark occurrence missed")
            .accessibilityIdentifier("\(idStem).checkbox")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: ListsSpacing.s1) {
                    Text(item.title)
                        .font(ListsTypography.body)
                        .foregroundStyle(ListsTokens.Foreground.secondary)
                        .lineLimit(2)
                    if let completedAt = occurrence.completedAt {
                        Text("Completed \(completedAt, format: .dateTime.month().day().year().hour().minute())")
                            .font(ListsTypography.footnote)
                            .foregroundStyle(ListsTokens.Foreground.secondary)
                    }
                    Text("Scheduled \(occurrence.scheduledAt, format: .dateTime.month().day().hour().minute())")
                        .font(ListsTypography.footnote)
                        .foregroundStyle(ListsTokens.Foreground.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint("Opens the recurring item")
            .accessibilityIdentifier(idStem)
        }
        .padding(.vertical, ListsDensity.rowPadY)
        .padding(.horizontal, ListsDensity.rowPadX)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
