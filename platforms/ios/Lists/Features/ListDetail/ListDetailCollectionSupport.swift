import SwiftUI
import UIKit

enum ListDetailLayout {
    /// Outer row/header edge aligned to the large navigation title. The title
    /// sits at the nav bar's standard layout margin (`rowPadX`, 16pt), so the
    /// body uses the same inset — matching the trailing edge for symmetry.
    static let leadingEdge: CGFloat = ListsDensity.rowPadX
    static let trailingEdge: CGFloat = ListsDensity.rowPadX
    static let indentStep: CGFloat = ListsNesting.indentStep
    /// Columns need a denser vertical rhythm than the full-width list. This
    /// leaves 6pt between neighboring row contents instead of 20pt while
    /// preserving the regular List presentation unchanged.
    static let columnRowPadY: CGFloat = 3
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

    /// In Columns mode, create at the end of the column nearest the viewport
    /// center. Returns nil outside Columns mode so the caller can keep the
    /// ordinary unsectioned-list behavior.
    func createInlineItemInPreferredColumn() -> UUID? {
        coordinator?.createInlineItemInPreferredColumn()
    }

    /// Section used by Quick Capture when it is opened from Columns mode.
    /// The synthetic Others column intentionally maps back to nil.
    func preferredSectionForCapture() -> String? {
        coordinator?.preferredColumnSectionKey().flatMap {
            $0 == listDetailUncategorizedKey ? nil : $0
        }
    }
}

extension ListDetailCollectionView.Coordinator {
    // MARK: FAB-drag inline create

    func createInlineItemAtDrag(globalPoint: CGPoint) -> UUID? {
        guard let parent = parent, let cv = collectionView else {
            clearItemDropTarget()
            return nil
        }
        guard ItemTypePolicy.allEnabled.allowsInlineCreation(parent.defaultNewItemType) else {
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

    func createInlineItemInPreferredColumn() -> UUID? {
        guard let parent,
              parent.presentation == .columns,
              ItemTypePolicy.allEnabled.allowsInlineCreation(parent.defaultNewItemType),
              let key = preferredColumnSectionKey() else {
            return nil
        }
        if !parent.prefs.sectionExpanded(key, in: parent.listId) {
            parent.prefs.setSectionExpanded(true, sectionId: key, in: parent.listId)
        }
        let section = key == listDetailUncategorizedKey ? nil : key
        return parent.store.addInlineItem(
            type: parent.defaultNewItemType,
            listId: parent.listId,
            section: section
        )
    }

    func preferredColumnSectionKey() -> String? {
        guard parent?.presentation == .columns,
              let layout = collectionView?.collectionViewLayout as? ListDetailColumnsLayout,
              let sectionIndex = layout.sectionNearestVisibleCenter() else {
            return nil
        }
        let snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.indices.contains(sectionIndex),
              case .section(let key) = snapshot.sectionIdentifiers[sectionIndex] else {
            return nil
        }
        return key
    }
}

/// Plain `UICollectionViewController` host. List presentation explicitly
/// associates the collection with the SwiftUI navigation host so its large
/// title follows normal system scroll-edge behavior. Columns intentionally do
/// not: their outer board only moves horizontally, while vertical movement is
/// visually confined to an individual column beneath a stationary large title.
final class ListDetailCollectionViewController: UICollectionViewController {
    private var didConfigureNavigationScrollView = false
    private weak var navigationHost: UIViewController?
    var tracksNavigationBarScroll = true

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationScrollViewIfNeeded()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        configureNavigationScrollViewIfNeeded()
    }

    /// Find the view controller NavigationStack actually pushed (the one whose
    /// parent is the `UINavigationController`) and, for List presentation only,
    /// tell it to treat our collection view as the navigation content scroll view.
    private func configureNavigationScrollViewIfNeeded() {
        guard !didConfigureNavigationScrollView,
              let collectionView else { return }
        var node: UIViewController? = self
        while let current = node {
            if current.parent is UINavigationController {
                navigationHost = current
                if tracksNavigationBarScroll {
                    current.setContentScrollView(collectionView)
                } else {
                    // A preceding List presentation may have left this host
                    // associated with a vertically scrolled collection. Clear
                    // that relationship so Columns begins and remains at the
                    // large-title scroll edge.
                    current.setContentScrollView(nil)
                    current.navigationItem.largeTitleDisplayMode = .always
                    current.navigationController?.navigationBar.prefersLargeTitles = true
                    current.navigationController?.navigationBar.setNeedsLayout()
                    current.navigationController?.navigationBar.layoutIfNeeded()
                }
                didConfigureNavigationScrollView = true
                return
            }
            node = current.parent
        }
    }

    /// SwiftUI can rediscover a bouncing descendant scroll view after the
    /// initial hand-off. Re-clear that association while Columns moves so a
    /// column's rubber-band never collapses the fixed large list title.
    func maintainFixedColumnsNavigationEdge() {
        guard !tracksNavigationBarScroll, let navigationHost else { return }
        navigationHost.setContentScrollView(nil)
        navigationHost.navigationItem.largeTitleDisplayMode = .always
        navigationHost.navigationController?.navigationBar.prefersLargeTitles = true
    }

}
