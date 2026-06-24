import UIKit

/// Lets the SwiftUI host reach into the collection view's coordinator for the
/// FAB-drag-to-list path (which has no `UIDropSession`): hit-test the list under
/// the finger, highlight it, and read the drop target on release. Mirrors
/// `ListDetailBridge`. The coordinator registers itself on make/update.
@MainActor
final class SidebarListsBridge {
    weak var coordinator: SidebarListsCollectionView.Coordinator?

    /// Highlight the list row under the FAB-drag point and return its id (nil
    /// when over no row, clearing the highlight).
    @discardableResult
    func highlightListUnderFAB(globalPoint: CGPoint) -> String? {
        coordinator?.updateFABDragHighlight(globalPoint: globalPoint)
    }

    /// The list id under the FAB-drag point on release, or nil.
    func listIdUnderFAB(globalPoint: CGPoint) -> String? {
        coordinator?.listIdUnderFABDrag(globalPoint: globalPoint)
    }

    /// Tear down the FAB-drag highlight without acting on it.
    func cancelFABDragCue() {
        coordinator?.cancelFABDragCue()
    }
}
