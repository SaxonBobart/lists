import SwiftUI
import UIKit

struct DatabaseTableLine: Identifiable, Equatable {
    let id: String
    let title: String?
    let row: DatabaseQuery.Row?
    var minimumHeight: CGFloat? = nil
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.minimumHeight == rhs.minimumHeight && lhs.row?.item == rhs.row?.item
            && lhs.row?.depth == rhs.row?.depth && lhs.row?.isContext == rhs.row?.isContext
    }
}

/// One native scroll surface owns both axes. Bouncing is disabled only here.
struct BoundedDatabaseTable<Header: View, RowContent: View>: UIViewControllerRepresentable {
    let lines: [DatabaseTableLine]
    let keys: [String]
    let fields: [DatabaseField]
    let contentWidth: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    let dynamicTypeSize: DynamicTypeSize
    let colorScheme: ColorScheme
    @ViewBuilder let header: Header
    @ViewBuilder let rowContent: (DatabaseTableLine) -> RowContent

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UICollectionViewController {
        let controller = UICollectionViewController(collectionViewLayout: DatabaseTableLayout())
        let collection = controller.collectionView!
        collection.backgroundColor = .clear
        collection.bounces = false
        collection.alwaysBounceHorizontal = false
        collection.alwaysBounceVertical = false
        collection.keyboardDismissMode = .interactive
        collection.contentInsetAdjustmentBehavior = .never
        collection.accessibilityIdentifier = "database.table.scroll"
        context.coordinator.attach(collection)
        return controller
    }
    func updateUIViewController(_ controller: UICollectionViewController, context: Context) {
        context.coordinator.update(self, collection: controller.collectionView)
    }
    @MainActor final class Coordinator {
        var parent: BoundedDatabaseTable
        var previous: [String: DatabaseTableLine] = [:]
        var source: UICollectionViewDiffableDataSource<Int, String>?
        init(parent: BoundedDatabaseTable) { self.parent = parent }
        lazy var registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
            guard let self, let line = previous[id] else { return }
            cell.backgroundConfiguration = .clear()
            cell.contentConfiguration = UIHostingConfiguration {
                parent.rowContent(line).environment(\.dynamicTypeSize, parent.dynamicTypeSize)
                    .environment(\.colorScheme, parent.colorScheme).id(line.id)
            }.margins(.all, 0)
        }
        func attach(_ collection: UICollectionView) {
            collection.register(UICollectionViewCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
            let cellRegistration = registration
            source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, index, id in
                return collection.dequeueConfiguredReusableCell(using: cellRegistration, for: index, item: id)
            }
            source?.supplementaryViewProvider = { [weak self] collection, kind, index in
                let cell = collection.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: index) as! UICollectionViewCell
                self?.configureHeader(cell)
                return cell
            }
        }
        private func configureHeader(_ cell: UICollectionViewCell) {
            cell.contentConfiguration = UIHostingConfiguration {
                parent.header.environment(\.dynamicTypeSize, parent.dynamicTypeSize)
                    .environment(\.colorScheme, parent.colorScheme)
            }.margins(.all, 0)
        }
        func update(_ next: BoundedDatabaseTable, collection: UICollectionView) {
            let changedColumns = parent.keys != next.keys || parent.fields != next.fields
                || parent.dynamicTypeSize != next.dynamicTypeSize || parent.colorScheme != next.colorScheme
            let current = Dictionary(uniqueKeysWithValues: next.lines.map { ($0.id, $0) })
            let changed = next.lines.filter { previous[$0.id] != nil && (changedColumns || previous[$0.id] != $0) }.map(\.id)
            parent = next; previous = current
            if let layout = collection.collectionViewLayout as? DatabaseTableLayout {
                layout.setMetrics(width: next.contentWidth, headerHeight: next.headerHeight,
                    heights: next.lines.map { $0.row == nil ? next.headerHeight : $0.minimumHeight ?? next.rowHeight })
            }
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0]); snapshot.appendItems(next.lines.map(\.id)); snapshot.reconfigureItems(changed)
            source?.apply(snapshot, animatingDifferences: false)
            for case let cell as UICollectionViewCell in collection.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) { configureHeader(cell) }
        }
    }
}

/// Scrolling updates the pinned header without rebuilding cached row geometry.
@MainActor final class DatabaseTableLayout: UICollectionViewLayout {
    private var width: CGFloat = 0
    private var headerHeight: CGFloat = 44
    private var heights: [CGFloat] = []
    private var frames: [CGRect] = []
    private var size = CGSize.zero
    private var preparedWidth: CGFloat = -1
    private var metricsChanged = true
    func setMetrics(width: CGFloat, headerHeight: CGFloat, heights: [CGFloat]) {
        guard self.width != width || self.headerHeight != headerHeight || self.heights != heights else { return }
        self.width = width; self.headerHeight = headerHeight; self.heights = heights
        metricsChanged = true; invalidateLayout()
    }
    override func prepare() {
        guard let collectionView, metricsChanged || preparedWidth != collectionView.bounds.width else { return }
        metricsChanged = false; preparedWidth = collectionView.bounds.width
        let contentWidth = max(width, collectionView.bounds.width)
        var y = headerHeight
        frames = heights.map { height in
            defer { y += height }
            return CGRect(x: 0, y: y, width: contentWidth, height: height)
        }
        size = CGSize(width: contentWidth, height: y)
    }
    override var collectionViewContentSize: CGSize { size }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard frames.indices.contains(indexPath.item) else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frames[indexPath.item]
        return attributes
    }
    override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard kind == UICollectionView.elementKindSectionHeader else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: indexPath)
        attributes.frame = CGRect(x: 0, y: max(0, collectionView?.contentOffset.y ?? 0), width: size.width, height: headerHeight)
        attributes.zIndex = 1000
        return attributes
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // Binary search limits layout work to the visible rows.
        var low = 0, high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].maxY < rect.minY { low = middle + 1 } else { high = middle }
        }
        var result: [UICollectionViewLayoutAttributes] = []
        var index = low
        while index < frames.count && frames[index].minY <= rect.maxY {
            if let attributes = layoutAttributesForItem(at: IndexPath(item: index, section: 0)) { result.append(attributes) }
            index += 1
        }
        if let header = layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)) { result.append(header) }
        return result
    }
}
