import UIKit

/// Non-scrolling collection view that measures its full content height and
/// reports changes via a callback, so it can size itself inside the sidebar's
/// outer ScrollView.
///
/// The measurement is done asynchronously, never from the representable's
/// `sizeThatFits`. The list cells self-size via `UIHostingConfiguration`, so
/// laying them out renders SwiftUI; doing that synchronously while the outer
/// SwiftUI graph is mid-update trips an AttributeGraph precondition and crashes
/// during reorder drops. Deferring to a fresh main-queue turn guarantees we are
/// not nested in a SwiftUI update.
final class SelfSizingListsCollectionView: UICollectionView {
    var onContentHeightChange: ((CGFloat) -> Void)?
    private var lastReportedHeight: CGFloat = -1
    private var measureScheduled = false
    private var isMeasuring = false

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleMeasure()
    }

    /// Ask for a re-measure after the snapshot changes (rows added/removed).
    func setNeedsHeightMeasure() { scheduleMeasure() }

    private func scheduleMeasure() {
        guard !isMeasuring, !measureScheduled else { return }
        measureScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            measureScheduled = false
            measureAndReport()
        }
    }

    private func measureAndReport() {
        guard bounds.width > 0 else { return }
        isMeasuring = true
        let saved = bounds
        bounds = CGRect(origin: saved.origin, size: CGSize(width: saved.width, height: 10_000))
        layoutIfNeeded()
        let height = collectionViewLayout.collectionViewContentSize.height
        bounds = saved
        layoutIfNeeded()
        isMeasuring = false
        guard height > 0, abs(height - lastReportedHeight) > 0.5 else { return }
        lastReportedHeight = height
        onContentHeightChange?(height)
    }
}
