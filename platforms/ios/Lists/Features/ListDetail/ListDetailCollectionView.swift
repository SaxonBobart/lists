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

private enum ListDetailLayout {
    /// Outer row/header edge aligned to the large navigation title. The title
    /// sits at the nav bar's standard layout margin (`rowPadX`, 16pt), so the
    /// body uses the same inset — matching the trailing edge for symmetry.
    static let leadingEdge: CGFloat = ListsDensity.rowPadX
    static let trailingEdge: CGFloat = ListsDensity.rowPadX
    static let indentStep: CGFloat = ListsNesting.indentStep
}

/// Lets the SwiftUI host (`ListDetailView`) reach into the live coordinator —
/// used so a FAB drag can create an inline item at a resolved drop point +
/// indent. The coordinator registers itself here on make/update.
@MainActor
final class ListDetailBridge {
    weak var coordinator: ListDetailCollectionView.Coordinator?

    /// Create an empty inline task at the FAB-drag global point, positioned and
    /// indented with the same drop logic as moving an existing item. Returns
    /// the new id to focus, or nil to fall back to a plain "Others" create.
    func createInlineItemAtDrag(globalPoint: CGPoint) -> UUID? {
        coordinator?.createInlineItemAtDrag(globalPoint: globalPoint)
    }

    /// Update the live drop cue (gap + placement rendering) for the FAB drag
    /// at the given global point — identical to the cue shown while dragging
    /// an existing item.
    func updateInlineDragCue(globalPoint: CGPoint) {
        coordinator?.updateInlineDragCue(globalPoint: globalPoint)
    }

    /// Tear down the FAB-drag drop cue without creating anything (drag
    /// cancelled or resolved to no target).
    func cancelInlineDragCue() {
        coordinator?.cancelInlineDragCue()
    }
}

/// Plain `UICollectionViewController` host. The collection view is explicitly
/// associated (via `setContentScrollView`) with the SwiftUI hosting controller
/// that NavigationStack pushes us inside, so the navigation bar tracks our
/// scroll offset — which drives the large-title collapse-to-inline and the
/// liquid-glass scroll-edge effect as rows scroll beneath the bar. SwiftUI does
/// not auto-detect scroll views buried inside a `UIViewControllerRepresentable`,
/// hence the manual hand-off.
final class ListDetailCollectionViewController: UICollectionViewController {
    private var didAssociateScrollView = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        associateContentScrollViewIfNeeded()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        associateContentScrollViewIfNeeded()
    }

    /// Find the view controller NavigationStack actually pushed (the one whose
    /// parent is the `UINavigationController`) and tell it to treat our
    /// collection view as its content scroll view for the whole nav bar.
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

struct ListDetailCollectionView: UIViewControllerRepresentable {
    let store: ItemStore
    let listId: String
    var prefs: ListViewPreferences
    let listColor: Color
    /// Bridge for FAB-drag inline create (see `ListDetailBridge`).
    let bridge: ListDetailBridge
    @Binding var inSelectMode: Bool
    @Binding var selection: Set<UUID>
    /// Id of the row currently being edited inline (its text title + notes).
    /// When set, that row renders as `.editingItem` instead of `.item`.
    @Binding var editingItemId: UUID?
    /// Section key (UUID string) whose header is being renamed inline. When set,
    /// that header renders as `.editingSectionHeader` — a focused text field —
    /// instead of `.sectionHeader`. Used by "New Section" so you name the new
    /// section in place rather than through an alert.
    @Binding var editingSectionKey: String?
    let lingeringIds: Set<UUID>
    /// The item type a FAB-drag inline-create produces (per Settings).
    let defaultNewItemType: Item.ItemType

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
    /// Tapping a row's text (outside select mode) requests inline editing.
    let onBeginInlineEdit: (UUID) -> Void
    /// Inline editing ended for this id — host clears `editingItemId` only if
    /// it still points here (guards against a fast row-to-row hand-off).
    let onEndInlineEdit: (UUID) -> Void
    /// Inline section-header rename finished — host clears `editingSectionKey`.
    let onEndEditSection: () -> Void

    var list: ItemList? {
        store.lists.first(where: { $0.id == listId })
    }

    func makeUIViewController(context: Context) -> ListDetailCollectionViewController {
        let layout = makeLayout(context: context)
        let vc = ListDetailCollectionViewController(collectionViewLayout: layout)
        let cv = vc.collectionView!
        cv.backgroundColor = .clear
        cv.delegate = context.coordinator
        cv.dragDelegate = context.coordinator
        cv.dropDelegate = context.coordinator
        cv.dragInteractionEnabled = true
        cv.allowsSelection = false
        cv.alwaysBounceVertical = true
        cv.contentInsetAdjustmentBehavior = .automatic

        context.coordinator.parent = self
        bridge.coordinator = context.coordinator
        context.coordinator.setupDataSource(for: cv)
        context.coordinator.applySnapshot(animated: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: ListDetailCollectionViewController, context: Context) {
        uiViewController.collectionView.allowsSelection = false
        context.coordinator.parent = self
        bridge.coordinator = context.coordinator
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
        return UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
            section.contentInsets = .zero
            return section
        }
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
        /// A section header in inline-rename mode (focused text field). Distinct
        /// identity from `.sectionHeader` so flipping into/out of editing forces
        /// a fresh, auto-focusing cell — mirrors `.editingItem`.
        case editingSectionHeader(key: String)
        case sectionDropPlaceholder(id: String)
        case item(id: UUID, indent: Int)
        /// The single row currently in inline-edit mode. Distinct identity so
        /// live typing never triggers the `.item` content-reload diff (which
        /// would tear down the keyboard), and so swipe/drag/context-menu — all
        /// gated on `.item` — skip it.
        case editingItem(id: UUID, indent: Int)
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
        /// True only for the brief synchronous span in which we force-resign the
        /// inline editor before deleting its cell. Forcing the resign moves the
        /// keyboard, which can re-enter `applySnapshot`; this drops that nested
        /// (redundant) call so we never start a second `dataSource.apply`.
        private var isResigningEditingCell = false
        /// Render-relevant state for each item row at the last snapshot apply,
        /// keyed by its diffable `RowItem`. An item row's identity stays stable
        /// across content edits, so the data source won't re-run its cell
        /// registration on its own — this lets `applySnapshot` detect which
        /// still-present rows changed content and reload just those.
        private var renderedItemState: [RowItem: ItemRenderState] = [:]
        /// Set while a section header is being dragged. When non-nil, the
        /// snapshot rebuild drops every item from this section so the
        /// floating section travels alone with nothing visually lingering
        /// at its source position.
        private var draggingSectionKey: String?
        private var draggingSectionHeight: CGFloat = 44
        private var draggingItemId: UUID?
        /// Height of the row being dragged, measured once at lift. The drop
        /// gap that opens (and the placement cue that fills it) takes this
        /// height, so the cue looks like the row will slot in there.
        private var draggingRowHeight: CGFloat?
        /// Whether the dragged row has been removed from the list yet. We wait
        /// until the drag is actually *moving* (first drop-session update) —
        /// these rows share their long-press with a context menu, and hiding
        /// the row on the mere lift would blank it out when the menu opens.
        private var dragSourceHidden = false
        /// Finger x at lift + the lifted row's depth. Indent during the drag is
        /// chosen from the horizontal *travel* relative to these — grab a row
        /// anywhere and one indent-step left/right out/indents it — instead of
        /// mapping the finger's absolute screen x (which forced a drag to the
        /// screen edge to outdent). nil for FAB drags, which have no source row.
        private var dragGrabX: CGFloat?
        private var dragGrabDepth = 0
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
            /// Chosen depth at this gap, from touch.x. 0 = top-level, capped at
            /// `ListsNesting.maxDisplayDepth`.
            let indent: Int
        }

        private struct VisibleRow {
            let id: UUID
            let depth: Int
            var frame: CGRect
        }

        private enum ItemDropCueStyle: Equatable {
            case placement
            case nesting
        }

        private static let sectionDropPlaceholderId = "section-drop-placeholder"
        private static let itemDropCueHeight: CGFloat = 26
        private static let itemDropCueSpace: CGFloat = 34

        // MARK: Data source setup

        private func configureListCell(_ cell: UICollectionViewListCell) {
            cell.transform = .identity
            cell.preservesSuperviewLayoutMargins = false
            cell.directionalLayoutMargins = .zero
            cell.layoutMargins = .zero
            cell.contentView.preservesSuperviewLayoutMargins = false
            cell.contentView.directionalLayoutMargins = .zero
            cell.contentView.layoutMargins = .zero
        }

        func setupDataSource(for cv: UICollectionView) {
            self.collectionView = cv

            let subListsHeader = makeSubListsHeaderReg()
            let subListChild = makeSubListChildReg()
            let sectionHeader = makeSectionHeaderReg()
            let sectionDropPlaceholder = makeSectionDropPlaceholderReg()
            let item = makeItemReg()
            let editingItem = makeEditingItemReg()

            dataSource = UICollectionViewDiffableDataSource<SectionKey, RowItem>(collectionView: cv) {
                cv, indexPath, row in
                switch row {
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
                let displayName = parent.sectionDisplayName(for: key) ?? ""
                let listId = parent.listId
                let prefs = parent.prefs
                let expanded = prefs.sectionExpanded(key, in: listId)
                let isFirstRow = (indexPath == IndexPath(item: 0, section: 0))
                let listColor = parent.listColor
                let onPromoteOthers = parent.onPromoteOthers
                let onRenameSection = parent.onRenameSection
                let onEndEditSection = parent.onEndEditSection
                cell.contentConfiguration = UIHostingConfiguration {
                    CVSectionHeaderRow(
                        sectionKey: key,
                        displayName: displayName,
                        isOthers: isOthers,
                        expanded: expanded,
                        showTopDivider: !isFirstRow,
                        listColor: listColor,
                        startEditing: startEditing,
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
                        },
                        leadingPadding: ListDetailLayout.leadingEdge,
                        trailingPadding: ListDetailLayout.trailingEdge,
                        onShowDetail: { _ in onShowItemDetail(item) },   // UI-1: parent-owned sheet
                        onBeginInlineEdit: { onBeginInlineEdit($0) }
                    )
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
                cell.contentConfiguration = UIHostingConfiguration {
                    InlineItemEditor(
                        item: item,
                        store: store,
                        listColor: listColor,
                        indent: indent,
                        leadingPadding: ListDetailLayout.leadingEdge,
                        trailingPadding: ListDetailLayout.trailingEdge,
                        onEndEditing: { onEndInlineEdit($0) },
                        onShowDetail: { onShowItemDetail($0) }
                    )
                }
                .margins(.all, 0)
                cell.accessibilityIdentifier = "list.item.editing.\(id.uuidString)"
            }
        }

        // MARK: Snapshot

        func applySnapshot(animated: Bool, reconfigure: [RowItem] = []) {
            // Drop the nested apply that force-resigning the editor can trigger
            // (see `isResigningEditingCell`); the outer call applies the current
            // snapshot, so the re-entrant one is redundant.
            guard !isResigningEditingCell else { return }
            guard let parent = parent, let list = parent.list else { return }
            // No early-return while an item drag is in flight: the snapshot is
            // rebuilt *without* the dragged subtree (see flattenWithChildren)
            // so the source row's space closes up, like a normal reorder.

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
            let showPastEvents = parent.prefs.showPastEvents(for: parent.listId)
            let visibleParents = parent.store.items.filter { item in
                item.listId == parent.listId
                    && item.deletedAt == nil
                    && item.parentId == nil
                    && (showCompleted || !item.isComplete || parent.lingeringIds.contains(item.id))
                    && (showPastEvents || !item.isRolledOffPastEvent())
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
                    let headerRow: RowItem = (!isOthers && key == parent.editingSectionKey)
                        ? .editingSectionHeader(key: key)
                        : .sectionHeader(key: key)
                    snapshot.appendItems([headerRow], toSection: sectionId)
                }

                let userExpanded = showHeader ? parent.prefs.sectionExpanded(key, in: parent.listId) : true
                // Collapse only the section being dragged. Every other
                // section honors the user's expand-state preference so the
                // surrounding context stays visible during a reorder.
                let isDragging = (key == draggingKey)
                let expanded = userExpanded && !isDragging
                if expanded {
                    let sorted = parent.applySort(entries)
                    // Only omit the dragged subtree once we've committed to
                    // hiding it (the drag is moving) — not during a bare lift
                    // that may turn into a context menu.
                    let flat = parent.flattenWithChildren(sorted,
                                                          draggingItemId: dragSourceHidden ? draggingItemId : nil)
                    let editingId = parent.editingItemId
                    snapshot.appendItems(flat.map { entry in
                        entry.item.id == editingId
                            ? .editingItem(id: entry.item.id, indent: entry.indent)
                            : .item(id: entry.item.id, indent: entry.indent)
                    }, toSection: sectionId)
                }
            }

            if dropTarget == .afterLast,
               let lastSection = snapshot.sectionIdentifiers.last {
                snapshot.appendItems([.sectionDropPlaceholder(id: Self.sectionDropPlaceholderId)], toSection: lastSection)
            }

            let present = Set(snapshot.itemIdentifiers)
            let previousItems = Set(dataSource.snapshot().itemIdentifiers)
            // A just-completed item kept on screen by the linger window (Show
            // Completed off) must be RELOADED, not reconfigured: an in-place
            // reconfigure of its `UIHostingConfiguration` cell during the
            // incomplete→complete transition blanks the hosted `ItemRow`, so
            // the row keeps its height but renders empty and looks like it
            // vanished. A full reload recreates the cell with fresh hosting
            // content that draws (the same way already-completed rows render
            // fine when Show Completed is on). Skip while dragging so we don't
            // disturb the drop-cue cell transforms.
            let dragInFlight = draggingItemId != nil || draggingSectionKey != nil
            let lingerRows: [RowItem] = dragInFlight ? [] : snapshot.itemIdentifiers.filter {
                if case .item(let id, _) = $0 { return parent.lingeringIds.contains(id) }
                return false
            }

            // An item row's diffable identity (`.item(id:indent:)`) stays
            // stable across content edits, so the data source won't re-run its
            // cell registration when only the underlying `Item` changes
            // (title, done, flag, priority, due, notes, …). Without this,
            // edits made in the detail sheet — and ticking / un-ticking a task
            // while "Show Completed" is on — don't surface until the list is
            // rebuilt by leaving and re-entering. Diff each still-present
            // row's render state against the last apply and RELOAD the changed
            // ones (reload, not reconfigure, for the same blanking reason as
            // the linger rows). Insertions and moves are animated by the data
            // source itself, so only rows present last time are considered.
            var changedContentRows: [RowItem] = []
            if !dragInFlight {
                let parentsWithChildren: Set<UUID> = Set(
                    parent.store.items.compactMap { $0.deletedAt == nil ? $0.parentId : nil }
                )
                var nextRendered: [RowItem: ItemRenderState] = [:]
                for row in snapshot.itemIdentifiers {
                    guard case .item(let id, let indent) = row,
                          let item = parent.store.item(id) else { continue }
                    let state = ItemRenderState(
                        item: item,
                        indent: indent,
                        isOverdue: parent.isOverdue(item),
                        inSelectMode: parent.inSelectMode,
                        isSelected: parent.selection.contains(id),
                        isExpanded: parent.prefs.itemExpanded(id.uuidString, in: parent.listId),
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

            // Diffable won't re-run a cell's registration when its identifier is
            // unchanged, so content-only changes (e.g. a chevron rotating after
            // a collapse toggle) need an explicit reconfigure.
            let reloadRows = lingerRows + changedContentRows
            let reconfigureRows = reconfigure.filter { present.contains($0) && !reloadRows.contains($0) }
            if !reconfigureRows.isEmpty {
                snapshot.reconfigureItems(reconfigureRows)
            }
            if !reloadRows.isEmpty {
                snapshot.reloadItems(reloadRows)
            }

            // If this diff removes the inline-editing cell while its text view is
            // still the first responder, UIKit throws "the first responder
            // contained inside of a deleted section or item refused to resign"
            // (ⓘ tap, ✓ commit, or collapsing the editing item's section all hit
            // this). Force-resign first so the cell we're about to delete no
            // longer owns the first responder. Guarded against the re-entrant
            // apply this resign can spin up via keyboard tracking.
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

        private func itemDropCueIndent(for target: ItemDropTarget?) -> Int {
            guard let target else { return 0 }
            switch target {
            case .nestInto(let id):
                return depthOf(id) + 1
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

        /// Color for each indent level, cycling VS Code-style.
        private static func indentLevelColor(for depth: Int) -> UIColor {
            if depth >= 8 { return .systemGray }
            switch depth {
            case 1:  return .systemGreen
            case 2:  return .systemYellow
            case 3:  return .systemOrange
            case 4:  return .systemRed
            case 5:  return .systemPink
            case 6:  return .systemPurple
            case 7:  return .systemBlue
            default: return .systemCyan
            }
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
                // Thin vertical bar at the left edge of the text at this indent level.
                let leading = ListDetailLayout.leadingEdge + CGFloat(gap.indent) * ListDetailLayout.indentStep
                let space = draggingRowHeight ?? Self.itemDropCueSpace
                let barWidth: CGFloat = 3
                let inset: CGFloat = 3
                let frame = CGRect(
                    x: leading,
                    y: gy + inset,
                    width: barWidth,
                    height: max(0, space - inset * 2)
                )
                applyItemDropTransforms(after: gy, in: collectionView)
                showItemDropCue(frame: frame,
                                color: Self.indentLevelColor(for: gap.indent),
                                style: .placement,
                                in: collectionView)
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

            if style == .nesting {
                cue.layer.cornerRadius = 8
                cue.backgroundColor = color.withAlphaComponent(0.16)
                cue.layer.borderColor = color.withAlphaComponent(0.35).cgColor
                cue.layer.borderWidth = 0
            } else {
                // Capsule indent bar — fully rounded on both ends.
                cue.layer.cornerRadius = frame.width / 2
                cue.backgroundColor = color.withAlphaComponent(0.85)
                cue.layer.borderColor = UIColor.clear.cgColor
                cue.layer.borderWidth = 0
            }
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
            let shift = draggingRowHeight ?? Self.itemDropCueSpace
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
                dragSourceHidden = false
                dragGrabX = session.location(in: collectionView).x
                dragGrabDepth = indent
                // The dragged row is deleted from the list once the drag moves
                // (see computeDropProposal), which also kills UIKit's default
                // cell-backed preview. So give UIKit a cell-INDEPENDENT preview
                // rendered to an image. `drawHierarchy(afterScreenUpdates:true)`
                // is the one snapshot path that captures SwiftUI-hosted content
                // — `snapshotView`/`layer.render` come back black.
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
                clearItemDropTarget()
                // NOTE: the dragged subtree is removed from the list lazily,
                // on the first drop-session update (see computeDropProposal) —
                // i.e. only once the item is actually being moved. These rows
                // share their long-press with a context menu; removing the row
                // on the bare lift blanked it out whenever the menu opened.
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
                // Restore the dragged subtree only if it was actually hidden
                // and the drag was cancelled (a committed drop clears
                // draggingItemId in performDropWith first and rebuilds via the
                // store update).
                let needsRestore = self.draggingItemId != nil && self.dragSourceHidden
                if self.draggingSectionKey != nil || self.sectionDropTarget != nil {
                    self.draggingSectionKey = nil
                    self.sectionDropTarget = nil
                    self.applySnapshot(animated: true)
                }
                self.draggingItemId = nil
                self.draggingRowHeight = nil
                self.dragSourceHidden = false
                self.dragGrabX = nil
                self.clearItemDropTarget()
                if needsRestore {
                    self.applySnapshot(animated: true)
                }
            }
        }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
            // Restore the dragged row if it was hidden and the drop was cancelled
            // (performDropWith clears draggingItemId before this fires on a
            // successful drop, so needsRestore is false in that path).
            let needsRestore = draggingItemId != nil && dragSourceHidden
            draggingItemId = nil
            draggingRowHeight = nil
            dragSourceHidden = false
            dragGrabX = nil
            clearSectionDropTarget()
            clearItemDropTarget()
            if needsRestore {
                applySnapshot(animated: true)
            }
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

        /// Remove the dragged subtree from the list the first time the drag
        /// actually moves, so its space closes up. Done once per drag; the
        /// lift preview is already committed by now, so the floating preview
        /// isn't orphaned.
        private func hideDraggedSourceIfNeeded() {
            guard draggingItemId != nil, !dragSourceHidden else { return }
            dragSourceHidden = true
            applySnapshot(animated: true)
        }

        private func computeDropProposal(collectionView: UICollectionView, session: UIDropSession, destination: IndexPath?) -> UICollectionViewDropProposal {
            guard let dragItem = session.localDragSession?.items.first,
                  let sourceRow = dragItem.localObject as? RowItem else {
                return UICollectionViewDropProposal(operation: .cancel)
            }

            if case .item(let id, _) = sourceRow {
                let target = resolvedItemDropTarget(collectionView: collectionView, session: session, sourceId: id)
                setItemDropTarget(target, in: collectionView)
                // Now that the item is genuinely being dragged (not just lifted
                // for the context menu), collapse its row out of the list.
                hideDraggedSourceIfNeeded()
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
            resolvedItemDropTarget(collectionView: collectionView,
                                   touch: session.location(in: collectionView),
                                   sourceId: sourceId)
        }

        /// Touch-based core, shared by the live drag session and the
        /// FAB-drag inline-create path (which has no `UIDropSession`).
        private func resolvedItemDropTarget(collectionView: UICollectionView,
                                            touch: CGPoint,
                                            sourceId: UUID) -> ItemDropTarget? {
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

            // 1. Touch INSIDE a row's frame.
            //    Top half  → gap above; bottom half → gap below.
            //    Horizontal position drives indent throughout — no separate nesting zone.
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
                    // Add slack for the removed dragged row so you can still
                    // position below the last visible item.
                    return collectionView.contentSize.height
                        + (draggingRowHeight ?? Self.itemDropCueSpace)
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
        /// For a row drag, the indent is the lifted row's depth plus one level
        /// per `indentStep` of horizontal travel from the grab point — relative
        /// motion, so it works the same wherever on the row the finger grabbed.
        /// A FAB drag has no grab origin and falls back to the absolute mapping
        /// (one level per step from the leading content edge). Either way the
        /// chosen depth is clamped by:
        ///   - `rowAbove.depth + 1` — can't be deeper than one child of the
        ///     row above (capped at `ListsNesting.maxDisplayDepth`).
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
            let raw: Int
            if let grabX = dragGrabX {
                raw = dragGrabDepth + Int(((touchX - grabX) / ListDetailLayout.indentStep).rounded())
            } else {
                raw = Int(floor((touchX - ListDetailLayout.leadingEdge) / ListDetailLayout.indentStep))
            }
            let maxByAbove = rowAboveDepth + 1
            let maxIndent = min(maxByAbove, ListsNesting.maxDisplayDepth)  // drag stops here; use Move-to for deeper
            let minIndent = max(0, min(rowBelowDepth ?? 0, maxIndent))
            return max(minIndent, min(raw, maxIndent))
        }

        private func presentMoveToParent(for item: Item, store: ItemStore) {
            var top = collectionView?.window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            guard let presenter = top else { return }
            let picker = MoveToParentPicker(item: item, store: store)
            let host = UIHostingController(rootView: picker)
            host.modalPresentationStyle = .fullScreen
            presenter.present(host, animated: true)
        }

        private func canNestItem(_ sourceId: UUID, inside targetId: UUID) -> Bool {
            targetId != sourceId
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
                      let item = parent.store.item(id) else {
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
            dragSourceHidden = false
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
                  let item = parent.store.item(id) else {
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
                guard let item = parent.store.item(id) else { return nil }
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

                // "Open" reads as "open this as its page" for the document types;
                // habits keep "Details" — their ⓘ leads to the classic detail screen.
                let details = UIContextualAction(
                    style: .normal,
                    title: item.type == .habit ? "Details" : "Open"
                ) { _, _, completion in
                    onShowItemDetail(item)
                    completion(true)
                }
                details.image = UIImage(systemName: item.type == .habit ? "info.circle" : "text.document")
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
                  let item = parent.store.item(id) else { return nil }
            let store = parent.store

            let parentPicker = UIContextualAction(style: .normal, title: "Move to…") { [weak self] _, _, completion in
                completion(true)
                self?.presentMoveToParent(for: item, store: parent.store)
            }
            parentPicker.image = UIImage(systemName: "list.bullet.indent")
            parentPicker.backgroundColor = UIColor(ListsTokens.accent)

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
                let config = UISwipeActionsConfiguration(actions: [outdent, parentPicker])
                config.performsFirstActionWithFullSwipe = false
                return config
            }

            let config = UISwipeActionsConfiguration(actions: [parentPicker])
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

        // MARK: FAB-drag inline create

        func createInlineItemAtDrag(globalPoint: CGPoint) -> UUID? {
            guard let parent = parent, let cv = collectionView else {
                clearItemDropTarget()
                return nil
            }
            let local = cv.convert(globalPoint, from: nil)
            guard let target = resolvedItemDropTarget(collectionView: cv, touch: local, sourceId: UUID()) else {
                clearItemDropTarget()
                return nil
            }
            let section: String?
            switch target {
            case .nestInto(let parentId):
                section = parent.store.item(parentId)?.section
            case .gap(let gap):
                section = (gap.sectionKey == listDetailUncategorizedKey) ? nil : gap.sectionKey
            }
            let type = parent.defaultNewItemType
            let newId = parent.store.addInlineItem(type: type, listId: parent.listId, section: section)
            // Tear down the live cue before the reorder rebuilds the snapshot.
            clearItemDropTarget()
            // Reuse the proven reorder to set parentId + sortIndex at the slot.
            _ = performItemReorder(itemId: newId, dropTarget: target)
            return newId
        }

        /// Live drop cue for a FAB drag. Resolves the target under the finger
        /// (no `UIDropSession` — there is no source row) and renders the same
        /// gap + placement cue used when dragging an existing item.
        func updateInlineDragCue(globalPoint: CGPoint) {
            guard let cv = collectionView else { return }
            let local = cv.convert(globalPoint, from: nil)
            let target = resolvedItemDropTarget(collectionView: cv, touch: local, sourceId: UUID())
            setItemDropTarget(target, in: cv)
        }

        func cancelInlineDragCue() {
            clearItemDropTarget()
        }

        // MARK: Keyboard avoidance — deliberately absent

        // Do NOT add manual keyboard handling (contentInset.bottom from
        // keyboard notifications, scroll-editing-row-into-view calls) here.
        // On iOS 26+ UIKit manages both itself: it grows the scroll view's
        // bottom inset for the keyboard AND reveals the first responder.
        // A manual inset STACKS with the system one; UIKit then computes a
        // keyboard-shrunken visible area smaller than the editing cell and
        // its reveal top-anchors the row under the nav bar — the "list jumps
        // to the top when editing starts" bug (diagnosed 2026-06-11 via
        // on-sim logging: system insetBottom reached 756pt = ours + UIKit's).

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
            var sectionChanged = false

            if copy.section != newItemSection {
                copy.section = newItemSection
                changed = true
                sectionChanged = true
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
            if sectionItemIds.isEmpty, !parent.prefs.sectionExpanded(sectionKey, in: parent.listId) {
                sectionItemIds = parent.store.items
                    .filter { item in
                        item.listId == parent.listId
                            && item.deletedAt == nil
                            && item.parentId == nil
                            && ((item.section ?? listDetailUncategorizedKey) == sectionKey)
                            && item.id != itemId
                    }
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .map(\.id)
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
            // The moved item's children render under it regardless of their own
            // section, so carry the whole subtree to the new section — else they
            // keep the old section id and get deleted with it.
            if sectionChanged {
                store.applySectionCascadeSync(toDescendantsOf: itemId, section: newItemSection)
            }
            if prefs.sort(for: listId) != .manual {
                prefs.setSort(.manual, for: listId)
            }
            let expandedTargetSection = !prefs.sectionExpanded(sectionKey, in: listId)
            if expandedTargetSection {
                prefs.setSectionExpanded(true, sectionId: sectionKey, in: listId)
            }
            store.applyReorderItemsSync(in: listId, flatOrderedIds: fullOrder)
            applySnapshot(
                animated: false,
                reconfigure: expandedTargetSection ? [.sectionHeader(key: sectionKey)] : []
            )
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
    /// Everything `makeItemReg` feeds into an `ItemRow` that affects how the
    /// row draws. `applySnapshot` compares this against the previous apply to
    /// reload rows whose visible content changed even though their diffable
    /// identity (`RowItem.item(id:indent:)`) did not.
    struct ItemRenderState: Equatable {
        let item: Item
        let indent: Int
        let isOverdue: Bool
        let inSelectMode: Bool
        let isSelected: Bool
        let isExpanded: Bool
        /// Drives the trailing collapse chevron — depends on *other* items'
        /// `parentId`, so it isn't covered by `item` equality alone.
        let hasChildren: Bool
    }

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

    func flattenWithChildren(_ parents: [Item],
                             draggingItemId: UUID? = nil) -> [(item: Item, indent: Int)] {
        var out: [(Item, Int)] = []
        let showCompleted = prefs.showCompleted(for: listId)
        let showPastEvents = prefs.showPastEvents(for: listId)
        let lingering = lingeringIds
        let isChildVisible: (Item) -> Bool = { item in
            item.deletedAt == nil
                && (showCompleted || !item.isComplete || lingering.contains(item.id))
                && (showPastEvents || !item.isRolledOffPastEvent())
        }
        // Iterative DFS — handles arbitrary depth. The visited set breaks any
        // cycles in the parent chain (e.g. item accidentally reparented under
        // one of its own descendants) so the traversal always terminates.
        var visited = Set<UUID>()
        // Stack stores (item, depth); reversed so we pop items in order.
        var stack = parents
            .filter { $0.id != draggingItemId }
            .reversed()
            .map { ($0, 0) }
        while let (item, depth) = stack.popLast() {
            guard !visited.contains(item.id) else { continue }
            visited.insert(item.id)
            out.append((item, depth))
            guard prefs.itemExpanded(item.id.uuidString, in: listId) else { continue }
            let children = store.items
                .filter { $0.parentId == item.id && isChildVisible($0) && $0.id != draggingItemId }
                .sorted { $0.sortIndex < $1.sortIndex }
            for child in children.reversed() {
                stack.append((child, depth + 1))
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
            Text("Sublists")
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
        .padding(.leading, ListDetailLayout.leadingEdge)
        .padding(.trailing, ListDetailLayout.trailingEdge)
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
        // trailing = leadingEdge to make the two share an x-position.
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
            .padding(.leading, ListDetailLayout.leadingEdge)
            .padding(.trailing, ListDetailLayout.trailingEdge)
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
    /// True for the `.editingSectionHeader` variant — open straight into the
    /// focused rename field (used by "New Section"). The placeholder shows the
    /// seeded name so an empty commit just keeps it.
    var startEditing: Bool = false
    let onToggleExpanded: () -> Void
    let onCommitRename: (String) -> Void
    /// Called when an inline rename finishes (commit or blur) so the host can
    /// clear `editingSectionKey`. No-op for tap-to-rename on a static header.
    var onEndEditing: () -> Void = {}

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
                    .padding(.leading, ListDetailLayout.leadingEdge)
                    .padding(.trailing, ListDetailLayout.trailingEdge)
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
            .padding(.leading, ListDetailLayout.leadingEdge)
            .padding(.trailing, ListDetailLayout.trailingEdge)
        }
        .padding(.vertical, 2)
        .onAppear {
            // The `.editingSectionHeader` variant opens straight into editing
            // with an empty field (the seeded name shows as the placeholder).
            if startEditing, !isRenaming {
                renameText = ""
                isRenaming = true
                DispatchQueue.main.async { renameFocused = true }
            }
        }
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
        onEndEditing()
    }
}
