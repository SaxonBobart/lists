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
    let moveSession: ItemMoveSession

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
    let onMoveShelfDragCandidateChanged: (Item?) -> Void
    /// Tapping a row's text (outside select mode) requests inline editing.
    let onBeginInlineEdit: (UUID) -> Void
    let onBeginMove: (Item) -> Void
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
        var isResigningEditingCell = false
        /// Render-relevant state for each item row at the last snapshot apply,
        /// keyed by its diffable `RowItem`. An item row's identity stays stable
        /// across content edits, so the data source won't re-run its cell
        /// registration on its own — this lets `applySnapshot` detect which
        /// still-present rows changed content and reload just those.
        var renderedItemState: [RowItem: ItemRenderState] = [:]
        /// Set while a section header is being dragged. When non-nil, the
        /// snapshot rebuild drops every item from this section so the
        /// floating section travels alone with nothing visually lingering
        /// at its source position.
        var draggingSectionKey: String?
        var draggingSectionHeight: CGFloat = 44
        var draggingItemId: UUID?
        /// Height of the row being dragged, measured once at lift. The drop
        /// gap that opens (and the placement cue that fills it) takes this
        /// height, so the cue looks like the row will slot in there.
        var draggingRowHeight: CGFloat?
        /// Whether the dragged row has been removed from the list yet. We wait
        /// until the drag is actually *moving* (first drop-session update) —
        /// these rows share their long-press with a context menu, and hiding
        /// the row on the mere lift would blank it out when the menu opens.
        var dragSourceHidden = false
        /// Finger x at lift + the lifted row's depth. Indent during the drag is
        /// chosen from the horizontal *travel* relative to these — grab a row
        /// anywhere and one indent-step left/right out/indents it — instead of
        /// mapping the finger's absolute screen x (which forced a drag to the
        /// screen edge to outdent). nil for FAB drags, which have no source row.
        var dragGrabX: CGFloat?
        var dragGrabDepth = 0
        var sectionDropTarget: SectionDropTarget?
        var itemDropTarget: ItemDropTarget?
        var itemDropCueView: UIView?
        var itemDropShiftedCells: [UICollectionViewCell] = []

        static let sectionDropPlaceholderId = "section-drop-placeholder"
        static let itemDropCueSpace: CGFloat = 34

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

    }
}
