import UIKit

/// List cell with a real primary accessibility action. The visual content is
/// SwiftUI-hosted, while row navigation is owned by the collection view.
final class SidebarListCollectionCell: UICollectionViewListCell {
    var onAccessibilityActivate: (() -> Void)?

    override func prepareForReuse() {
        super.prepareForReuse()
        onAccessibilityActivate = nil
    }

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?()
        return true
    }
}
