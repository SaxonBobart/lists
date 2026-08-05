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
    private var maximumScrollOffsetsBySection: [Int: CGFloat] = [:]
    private var scrollOffsetsBySection: [Int: CGFloat] = [:]
    private var activeColumnSection: Int?
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
        maximumScrollOffsetsBySection.removeAll(keepingCapacity: true)
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
        let globalScrollOffset = max(
            0,
            collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        )
        let minimumColumnHeight = max(
            260,
            collectionView.bounds.height
                - collectionView.adjustedContentInset.top
                - collectionView.adjustedContentInset.bottom
                - columnsStartY
                - outerInset
        )
        for (columnIndex, sectionIndex) in columnSectionIndices.enumerated() {
            let x = outerInset + CGFloat(columnIndex) * (columnWidth + columnSpacing)
            var y = columnsStartY

            for itemIndex in 0..<collectionView.numberOfItems(inSection: sectionIndex) {
                let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                let height = resolvedHeight(at: indexPath)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                let columnScrollOffset = sectionIndex == activeColumnSection
                    ? globalScrollOffset
                    : scrollOffsetsBySection[sectionIndex, default: 0]
                attributes.frame = CGRect(
                    x: x,
                    y: y + globalScrollOffset - columnScrollOffset,
                    width: columnWidth,
                    height: height
                )
                attributes.zIndex = 1
                itemAttributes[indexPath] = attributes
                y += height
            }

            let naturalColumnHeight = y - columnsStartY + outerInset
            let columnHeight = max(minimumColumnHeight, naturalColumnHeight)
            maximumScrollOffsetsBySection[sectionIndex] = max(
                0,
                naturalColumnHeight - minimumColumnHeight
                    + (naturalColumnHeight > minimumColumnHeight ? boardBottomInset : 0)
            )
            let columnFrame = CGRect(
                x: x,
                y: columnsStartY + globalScrollOffset,
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
                1,
                collectionView.bounds.height
                    - collectionView.adjustedContentInset.top
                    - collectionView.adjustedContentInset.bottom
                    + (maximumScrollOffsetsBySection.values.max() ?? 0)
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
            || abs(newBounds.minY - collectionView.bounds.minY) > 0.5
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
        guard let collectionView else {
            return proposedContentOffset
        }

        let maximumY = maximumScrollOffsetsBySection[activeColumnSection ?? -1, default: 0]
            - collectionView.adjustedContentInset.top
        let proposedY = min(
            maximumY,
            max(-collectionView.adjustedContentInset.top, proposedContentOffset.y)
        )
        guard !orderedColumnSections.isEmpty,
              abs(velocity.x) >= abs(velocity.y) * 0.55 else {
            return CGPoint(x: proposedContentOffset.x, y: proposedY)
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
        guard !snapOffsets.isEmpty else {
            return CGPoint(x: proposedContentOffset.x, y: proposedY)
        }

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

        return CGPoint(x: targetX, y: proposedY)
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

    /// Selects the column whose vertical offset the collection view will drive.
    /// Every other column keeps its stored position while horizontal scrolling
    /// remains shared by the board.
    func activateColumn(at point: CGPoint) {
        guard let collectionView else { return }

        if let activeColumnSection {
            let currentOffset = max(
                0,
                collectionView.contentOffset.y + collectionView.adjustedContentInset.top
            )
            scrollOffsetsBySection[activeColumnSection] = min(
                currentOffset,
                maximumScrollOffsetsBySection[activeColumnSection, default: 0]
            )
        }

        guard let section = orderedColumnSections.first(where: {
            (columnFramesBySection[$0]?.minX ?? .greatestFiniteMagnitude) <= point.x
                && point.x <= (columnFramesBySection[$0]?.maxX ?? -.greatestFiniteMagnitude)
        }) else { return }

        activeColumnSection = section
        let restoredOffset = min(
            scrollOffsetsBySection[section, default: 0],
            maximumScrollOffsetsBySection[section, default: 0]
        )
        invalidateLayout()
        collectionView.setContentOffset(
            CGPoint(
                x: collectionView.contentOffset.x,
                y: restoredOffset - collectionView.adjustedContentInset.top
            ),
            animated: false
        )
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
