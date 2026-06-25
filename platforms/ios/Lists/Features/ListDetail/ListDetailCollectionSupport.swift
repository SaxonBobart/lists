import SwiftUI
import UIKit

enum ListDetailLayout {
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
