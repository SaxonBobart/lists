import UIKit

/// Two-dimensional collection layout used by a user list's Columns mode.
///
/// The existing diffable sections remain the source of truth: utility
/// sections (move destination and sublists) span the visible width above the
/// board, while every durable list section becomes one independently sized
/// column. Because the row cells and delegates are unchanged, Columns keeps
/// the same inline editing, hierarchy, swipe, selection, and drag behavior as
/// List mode.
final class ListDetailColumnsLayout: UICollectionViewLayout {
    static let columnBackgroundKind = "list.columns.background"

    typealias SectionIdentifier = ListDetailCollectionView.SectionKey
    typealias RowIdentifier = ListDetailCollectionView.RowItem

    var sectionIdentifierAt: ((Int) -> SectionIdentifier?)?
    var rowIdentifierAt: ((IndexPath) -> RowIdentifier?)?

    private let outerInset: CGFloat = 14
    private let columnSpacing: CGFloat = 12
    private let utilitySpacing: CGFloat = 10
    private let boardBottomInset: CGFloat = 104

    private var itemAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var backgroundAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var measuredHeights: [RowIdentifier: CGFloat] = [:]
    private var columnFramesBySection: [Int: CGRect] = [:]
    private var orderedColumnSections: [Int] = []
    private var preparedContentSize: CGSize = .zero
    private var lastPreparedBoundsSize: CGSize = .zero

    override init() {
        super.init()
        register(
            ListDetailColumnBackgroundView.self,
            forDecorationViewOfKind: Self.columnBackgroundKind
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        register(
            ListDetailColumnBackgroundView.self,
            forDecorationViewOfKind: Self.columnBackgroundKind
        )
    }

    override var collectionViewContentSize: CGSize {
        preparedContentSize
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }

        itemAttributes.removeAll(keepingCapacity: true)
        backgroundAttributes.removeAll(keepingCapacity: true)
        columnFramesBySection.removeAll(keepingCapacity: true)
        orderedColumnSections.removeAll(keepingCapacity: true)
        lastPreparedBoundsSize = collectionView.bounds.size

        let visibleWidth = max(1, collectionView.bounds.width)
        let fullRowWidth = max(1, visibleWidth - outerInset * 2)
        let columnWidth = resolvedColumnWidth(for: visibleWidth)

        var utilityY: CGFloat = 0
        var columnSectionIndices: [Int] = []

        for sectionIndex in 0..<collectionView.numberOfSections {
            guard let section = sectionIdentifierAt?(sectionIndex) else { continue }
            switch section {
            case .moveDestination, .subLists:
                let pinnedX = collectionView.bounds.minX + outerInset
                for itemIndex in 0..<collectionView.numberOfItems(inSection: sectionIndex) {
                    let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                    let height = resolvedHeight(at: indexPath)
                    let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                    attributes.frame = CGRect(
                        x: pinnedX,
                        y: utilityY,
                        width: fullRowWidth,
                        height: height
                    )
                    attributes.zIndex = 10
                    itemAttributes[indexPath] = attributes
                    utilityY += height
                }
                if collectionView.numberOfItems(inSection: sectionIndex) > 0 {
                    utilityY += utilitySpacing
                }
            case .section:
                columnSectionIndices.append(sectionIndex)
            }
        }

        let columnsStartY = utilityY
        let minimumColumnHeight = max(
            260,
            collectionView.bounds.height
                - collectionView.adjustedContentInset.top
                - collectionView.adjustedContentInset.bottom
                - columnsStartY
                - outerInset
        )
        var maximumBottom = columnsStartY + minimumColumnHeight

        for (columnIndex, sectionIndex) in columnSectionIndices.enumerated() {
            let x = outerInset + CGFloat(columnIndex) * (columnWidth + columnSpacing)
            var y = columnsStartY

            for itemIndex in 0..<collectionView.numberOfItems(inSection: sectionIndex) {
                let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                let height = resolvedHeight(at: indexPath)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                attributes.frame = CGRect(x: x, y: y, width: columnWidth, height: height)
                attributes.zIndex = 1
                itemAttributes[indexPath] = attributes
                y += height
            }

            let columnHeight = max(minimumColumnHeight, y - columnsStartY + outerInset)
            let columnFrame = CGRect(
                x: x,
                y: columnsStartY,
                width: columnWidth,
                height: columnHeight
            )
            columnFramesBySection[sectionIndex] = columnFrame
            orderedColumnSections.append(sectionIndex)

            let backgroundIndexPath = IndexPath(item: 0, section: sectionIndex)
            let background = UICollectionViewLayoutAttributes(
                forDecorationViewOfKind: Self.columnBackgroundKind,
                with: backgroundIndexPath
            )
            background.frame = columnFrame
            background.zIndex = -10
            backgroundAttributes[backgroundIndexPath] = background
            maximumBottom = max(maximumBottom, columnFrame.maxY)
        }

        let contentWidth: CGFloat
        if let lastSection = orderedColumnSections.last,
           let lastFrame = columnFramesBySection[lastSection] {
            contentWidth = max(visibleWidth, lastFrame.maxX + outerInset)
        } else {
            contentWidth = visibleWidth
        }
        preparedContentSize = CGSize(
            width: contentWidth,
            height: max(
                collectionView.bounds.height + 1,
                maximumBottom + boardBottomInset
            )
        )
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let cells = itemAttributes.values.filter { $0.frame.intersects(rect) }
        let backgrounds = backgroundAttributes.values.filter { $0.frame.intersects(rect) }
        return cells + backgrounds
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        itemAttributes[indexPath]
    }

    override func layoutAttributesForDecorationView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard elementKind == Self.columnBackgroundKind else { return nil }
        return backgroundAttributes[indexPath]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return true }
        return newBounds.size != lastPreparedBoundsSize
            || abs(newBounds.minX - collectionView.bounds.minX) > 0.5
    }

    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> Bool {
        guard preferredAttributes.representedElementCategory == .cell,
              let row = rowIdentifierAt?(preferredAttributes.indexPath) else {
            return false
        }

        // A column owns its width. Hosted SwiftUI content is free to choose
        // only its height.
        preferredAttributes.size.width = originalAttributes.size.width
        let preferredHeight = max(1, ceil(preferredAttributes.size.height))
        let previousHeight = measuredHeights[row]
            ?? originalAttributes.size.height
        guard abs(preferredHeight - previousHeight) > 0.5 else { return false }
        measuredHeights[row] = preferredHeight
        return true
    }

    override func invalidationContext(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(
            forPreferredLayoutAttributes: preferredAttributes,
            withOriginalAttributes: originalAttributes
        )
        // A height change shifts every row below it in that column and can
        // change the board's content height, so invalidate the cached cells.
        context.invalidateItems(at: Array(itemAttributes.keys))
        return context
    }

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView,
              !orderedColumnSections.isEmpty,
              abs(velocity.x) >= abs(velocity.y) * 0.55 else {
            return proposedContentOffset
        }

        let maximumX = max(
            0,
            collectionViewContentSize.width - collectionView.bounds.width
                + collectionView.adjustedContentInset.right
        )
        let snapOffsets = orderedColumnSections.compactMap { sectionIndex -> CGFloat? in
            guard let frame = columnFramesBySection[sectionIndex] else { return nil }
            return min(maximumX, max(0, frame.minX - outerInset))
        }
        guard !snapOffsets.isEmpty else { return proposedContentOffset }

        let proposedX = min(maximumX, max(0, proposedContentOffset.x))
        let targetX: CGFloat
        if velocity.x > 0.32 {
            targetX = snapOffsets.first(where: { $0 > collectionView.contentOffset.x + 1 })
                ?? snapOffsets.last!
        } else if velocity.x < -0.32 {
            targetX = snapOffsets.last(where: { $0 < collectionView.contentOffset.x - 1 })
                ?? snapOffsets.first!
        } else {
            targetX = snapOffsets.min(by: {
                abs($0 - proposedX) < abs($1 - proposedX)
            }) ?? proposedX
        }

        return CGPoint(x: targetX, y: proposedContentOffset.y)
    }

    func sectionNearestVisibleCenter() -> Int? {
        guard let collectionView else { return nil }
        let visibleCenterX = collectionView.bounds.midX
        return orderedColumnSections.min { lhs, rhs in
            let lhsDistance = abs((columnFramesBySection[lhs]?.midX ?? 0) - visibleCenterX)
            let rhsDistance = abs((columnFramesBySection[rhs]?.midX ?? 0) - visibleCenterX)
            return lhsDistance < rhsDistance
        }
    }

    func columnFrame(forSection section: Int) -> CGRect? {
        columnFramesBySection[section]
    }

    private func resolvedColumnWidth(for viewportWidth: CGFloat) -> CGFloat {
        if viewportWidth >= 700 {
            return min(380, max(300, (viewportWidth - outerInset * 2 - columnSpacing) / 2))
        }
        return min(360, max(276, viewportWidth * 0.84))
    }

    private func resolvedHeight(at indexPath: IndexPath) -> CGFloat {
        guard let row = rowIdentifierAt?(indexPath) else { return 58 }
        if let measured = measuredHeights[row] {
            return measured
        }
        switch row {
        case .moveNone:
            return 54
        case .subListsHeader:
            return 48
        case .subListChild:
            return 54
        case .sectionHeader, .editingSectionHeader:
            return 56
        case .sectionDropPlaceholder:
            return 0
        case .item:
            return 68
        case .editingItem:
            return 128
        }
    }
}

final class ListDetailColumnBackgroundView: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.borderWidth = 1 / max(1, traitCollection.displayScale)
        layer.borderColor = UIColor.separator
            .resolvedColor(with: traitCollection)
            .withAlphaComponent(0.45)
            .cgColor
    }

    private func configure() {
        isUserInteractionEnabled = false
        // Keep the full-height drop target that makes empty Kanban columns
        // useful, but let the app background dominate instead of filling most
        // of the screen with opaque grouped grey.
        backgroundColor = UIColor.secondarySystemGroupedBackground
            .withAlphaComponent(0.38)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        accessibilityIdentifier = "list.columns.background"
    }
}
