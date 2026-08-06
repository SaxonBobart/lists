import UIKit

/// Two-dimensional collection layout used by a user list's Columns mode.
///
/// The existing diffable sections remain the source of truth: utility
/// sections (move destination and sublists) span the visible width above the
/// board, while every durable list section becomes one fixed-height column
/// whose items keep an independent, clipped vertical offset below its pinned
/// header. Because the row cells and delegates are unchanged, Columns keeps
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
    private var itemViewportsBySection: [Int: CGRect] = [:]
    private var maximumScrollOffsetsBySection: [SectionIdentifier: CGFloat] = [:]
    private var scrollOffsetsBySection: [SectionIdentifier: CGFloat] = [:]
    private var activeColumnSection: SectionIdentifier?
    private var subListsSectionIndex: Int?
    private var subListsItemViewport: CGRect?
    private var subListsMaximumScrollOffset: CGFloat = 0
    private var subListsScrollOffset: CGFloat = 0
    private var subListsAreActive = false
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
        itemViewportsBySection.removeAll(keepingCapacity: true)
        maximumScrollOffsetsBySection.removeAll(keepingCapacity: true)
        subListsSectionIndex = nil
        subListsItemViewport = nil
        subListsMaximumScrollOffset = 0
        orderedColumnSections.removeAll(keepingCapacity: true)
        lastPreparedBoundsSize = collectionView.bounds.size

        let visibleWidth = max(1, collectionView.bounds.width)
        let fullRowWidth = max(1, visibleWidth - outerInset * 2)
        let columnWidth = resolvedColumnWidth(for: visibleWidth)
        // Keep the signed displacement while UIKit rubber-bands. Positive
        // values scroll the active column upward; negative values pull it
        // downward. Fixed board chrome and inactive columns counter-position
        // by this same value, so only the active column's items move.
        let globalScrollOffset = collectionView.contentOffset.y
            + collectionView.adjustedContentInset.top

        var utilityY: CGFloat = 0
        var columnSectionIndices: [Int] = []
        var pendingSubListsSectionIndex: Int?

        for sectionIndex in 0..<collectionView.numberOfSections {
            guard let section = sectionIdentifierAt?(sectionIndex) else { continue }
            switch section {
            case .moveDestination:
                let pinnedX = collectionView.bounds.minX + outerInset
                for itemIndex in 0..<collectionView.numberOfItems(inSection: sectionIndex) {
                    let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                    let height = resolvedHeight(at: indexPath)
                    let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                    attributes.frame = CGRect(
                        x: pinnedX,
                        y: utilityY + globalScrollOffset,
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
            case .subLists:
                pendingSubListsSectionIndex = sectionIndex
            case .section:
                columnSectionIndices.append(sectionIndex)
            }
        }

        if activeColumnSection == nil,
           let firstColumn = columnSectionIndices.first,
           let firstIdentifier = sectionIdentifierAt?(firstColumn) {
            activeColumnSection = firstIdentifier
        }
        if pendingSubListsSectionIndex == nil {
            subListsAreActive = false
            subListsScrollOffset = 0
        }

        if let sectionIndex = pendingSubListsSectionIndex,
           collectionView.numberOfItems(inSection: sectionIndex) > 0 {
            subListsSectionIndex = sectionIndex
            let startY = utilityY
            var naturalHeight: CGFloat = 0
            var headerHeight: CGFloat = 0
            for itemIndex in 0..<collectionView.numberOfItems(inSection: sectionIndex) {
                let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                let height = resolvedHeight(at: indexPath)
                if rowIdentifierAt?(indexPath) == .subListsHeader {
                    headerHeight = height
                }
                naturalHeight += height
            }

            let availableHeight = max(
                1,
                collectionView.bounds.height
                    - collectionView.adjustedContentInset.top
                    - collectionView.adjustedContentInset.bottom
            )
            let maximumRegionHeight = max(
                headerHeight,
                availableHeight - utilityY - utilitySpacing - outerInset - 260
            )
            let regionHeight = min(naturalHeight, maximumRegionHeight)
            let itemViewport = CGRect(
                x: collectionView.bounds.minX + outerInset,
                y: startY + headerHeight + globalScrollOffset,
                width: fullRowWidth,
                height: max(0, regionHeight - headerHeight)
            )
            subListsItemViewport = itemViewport
            subListsMaximumScrollOffset = max(0, naturalHeight - regionHeight)
            subListsScrollOffset = min(subListsScrollOffset, subListsMaximumScrollOffset)

            var itemY = startY
            for itemIndex in 0..<collectionView.numberOfItems(inSection: sectionIndex) {
                let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                let height = resolvedHeight(at: indexPath)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                if rowIdentifierAt?(indexPath) == .subListsHeader {
                    attributes.frame = CGRect(
                        x: collectionView.bounds.minX + outerInset,
                        y: itemY + globalScrollOffset,
                        width: fullRowWidth,
                        height: height
                    )
                    attributes.zIndex = 20
                } else {
                    let scrollOffset = subListsAreActive
                        ? globalScrollOffset
                        : subListsScrollOffset
                    attributes.frame = CGRect(
                        x: collectionView.bounds.minX + outerInset,
                        y: itemY + globalScrollOffset - scrollOffset,
                        width: fullRowWidth,
                        height: height
                    )
                    attributes.zIndex = 10
                }
                itemAttributes[indexPath] = attributes
                itemY += height
            }
            utilityY += regionHeight + utilitySpacing
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
        for (columnIndex, sectionIndex) in columnSectionIndices.enumerated() {
            guard let sectionIdentifier = sectionIdentifierAt?(sectionIndex) else { continue }
            let x = outerInset + CGFloat(columnIndex) * (columnWidth + columnSpacing)
            var y = columnsStartY
            var headerHeight: CGFloat = 0

            for itemIndex in 0..<collectionView.numberOfItems(inSection: sectionIndex) {
                let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                let height = resolvedHeight(at: indexPath)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                let row = rowIdentifierAt?(indexPath)
                if row?.isSectionHeader == true {
                    headerHeight = height
                    attributes.frame = CGRect(
                        x: x,
                        y: columnsStartY + globalScrollOffset,
                        width: columnWidth,
                        height: height
                    )
                    attributes.zIndex = 20
                } else {
                    let columnScrollOffset = !subListsAreActive
                        && sectionIdentifier == activeColumnSection
                        ? globalScrollOffset
                        : scrollOffsetsBySection[sectionIdentifier, default: 0]
                    attributes.frame = CGRect(
                        x: x,
                        y: y + globalScrollOffset - columnScrollOffset,
                        width: columnWidth,
                        height: height
                    )
                    attributes.zIndex = 1
                }
                itemAttributes[indexPath] = attributes
                y += height
            }

            let naturalColumnHeight = y - columnsStartY + outerInset
            maximumScrollOffsetsBySection[sectionIdentifier] = max(
                0,
                naturalColumnHeight - minimumColumnHeight
                    + (naturalColumnHeight > minimumColumnHeight ? boardBottomInset : 0)
            )
            let columnFrame = CGRect(
                x: x,
                y: columnsStartY + globalScrollOffset,
                width: columnWidth,
                height: minimumColumnHeight
            )
            columnFramesBySection[sectionIndex] = columnFrame
            itemViewportsBySection[sectionIndex] = CGRect(
                x: x,
                y: columnFrame.minY + headerHeight,
                width: columnWidth,
                height: max(0, columnFrame.height - headerHeight)
            )
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
                    + activeMaximumScrollOffset
            )
        )
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let cells = itemAttributes.values.filter { attributes in
            guard attributes.frame.intersects(rect),
                  let row = rowIdentifierAt?(attributes.indexPath) else { return false }
            switch row {
            case .subListChild:
                guard let subListsItemViewport else { return false }
                return attributes.frame.intersects(subListsItemViewport)
            case .item, .editingItem:
                guard let viewport = itemViewportsBySection[attributes.indexPath.section] else {
                    return false
                }
                return attributes.frame.intersects(viewport)
            default:
                return true
            }
        }
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

        let maximumY = activeMaximumScrollOffset
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

    func itemViewport(forSection section: Int) -> CGRect? {
        itemViewportsBySection[section]
    }

    func subListsViewport(forSection section: Int) -> CGRect? {
        guard section == subListsSectionIndex else { return nil }
        return subListsItemViewport
    }

    func subListsAreScrolled(displayScale: CGFloat) -> Bool {
        let offset: CGFloat
        if subListsAreActive, let collectionView {
            offset = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        } else {
            offset = subListsScrollOffset
        }
        return offset > 1 / max(1, displayScale)
    }

    func columnIsScrolled(sectionIndex: Int, displayScale: CGFloat) -> Bool {
        guard let collectionView else { return false }
        guard let sectionIdentifier = sectionIdentifierAt?(sectionIndex) else { return false }
        let effectiveActiveSection: SectionIdentifier? = activeColumnSection ?? orderedColumnSections.first
            .flatMap { sectionIdentifierAt?($0) }
        let offset: CGFloat
        if !subListsAreActive, sectionIdentifier == effectiveActiveSection {
            offset = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        } else {
            offset = scrollOffsetsBySection[sectionIdentifier, default: 0]
        }
        return offset > 1 / max(1, displayScale)
    }

    private var activeMaximumScrollOffset: CGFloat {
        if subListsAreActive {
            return subListsMaximumScrollOffset
        }
        if let activeColumnSection {
            return maximumScrollOffsetsBySection[activeColumnSection, default: 0]
        }
        guard let firstSection = orderedColumnSections.first,
              let identifier = sectionIdentifierAt?(firstSection) else { return 0 }
        return maximumScrollOffsetsBySection[identifier, default: 0]
    }

    /// Selects the column whose vertical offset the collection view will drive.
    /// Every other column keeps its stored position while horizontal scrolling
    /// remains shared by the board.
    func activateVerticalRegion(at point: CGPoint, targetsSubLists: Bool) {
        guard let collectionView else { return }

        let currentOffset = max(
            0,
            collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        )
        if subListsAreActive {
            subListsScrollOffset = min(currentOffset, subListsMaximumScrollOffset)
        } else if let activeColumnSection {
            scrollOffsetsBySection[activeColumnSection] = min(
                currentOffset,
                maximumScrollOffsetsBySection[activeColumnSection, default: 0]
            )
        }

        let hitsSubListsRegion = subListsItemViewport.map { viewport in
            CGRect(
                x: collectionView.bounds.minX,
                y: viewport.minY - resolvedSubListsHeaderHeight,
                width: collectionView.bounds.width,
                height: viewport.height + resolvedSubListsHeaderHeight
            ).contains(point)
        } ?? false
        if targetsSubLists || hitsSubListsRegion {
            guard !subListsAreActive else { return }
            subListsAreActive = true
            restoreVerticalOffset(subListsScrollOffset, in: collectionView)
            return
        }

        guard let section = orderedColumnSections.first(where: {
            (columnFramesBySection[$0]?.minX ?? .greatestFiniteMagnitude) <= point.x
                && point.x <= (columnFramesBySection[$0]?.maxX ?? -.greatestFiniteMagnitude)
        }) else { return }

        guard let sectionIdentifier = sectionIdentifierAt?(section) else { return }

        guard subListsAreActive || sectionIdentifier != activeColumnSection else { return }
        subListsAreActive = false
        activeColumnSection = sectionIdentifier
        let restoredOffset = min(
            scrollOffsetsBySection[sectionIdentifier, default: 0],
            maximumScrollOffsetsBySection[sectionIdentifier, default: 0]
        )
        restoreVerticalOffset(restoredOffset, in: collectionView)
    }

    private var resolvedSubListsHeaderHeight: CGFloat {
        guard let section = subListsSectionIndex,
              collectionView?.numberOfItems(inSection: section) ?? 0 > 0 else { return 0 }
        return resolvedHeight(at: IndexPath(item: 0, section: section))
    }

    private func restoreVerticalOffset(_ restoredOffset: CGFloat, in collectionView: UICollectionView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        invalidateLayout()
        collectionView.setContentOffset(
            CGPoint(
                x: collectionView.contentOffset.x,
                y: restoredOffset - collectionView.adjustedContentInset.top
            ),
            animated: false
        )
        collectionView.layoutIfNeeded()
        CATransaction.commit()
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
