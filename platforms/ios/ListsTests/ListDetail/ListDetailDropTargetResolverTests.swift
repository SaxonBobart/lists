import Testing
import UIKit
@testable import Lists

@MainActor
struct ListDetailDropTargetResolverTests {
    private let topSectionHeader = CGRect(x: 0, y: 48, width: 360, height: 52)
    private let middleRow = CGRect(x: 0, y: 116, width: 360, height: 54)
    private let lowerRow = CGRect(x: 0, y: 182, width: 360, height: 54)
    private let bottomSectionHeader = CGRect(x: 0, y: 260, width: 360, height: 52)
    private let secondSectionRow = CGRect(x: 0, y: 328, width: 360, height: 54)

    private func coordinator() -> ListDetailCollectionView.Coordinator {
        ListDetailCollectionView.Coordinator()
    }

    private func section(
        key: String,
        headerFrame: CGRect,
        rows: [ListDetailCollectionView.VisibleRow]
    ) -> ListDetailCollectionView.Coordinator.ItemDropSectionGeometry {
        .init(key: key, headerFrame: headerFrame, rows: rows)
    }

    @Test func dragInTopEmptySpaceTargetsFirstSectionGap() {
        let firstId = UUID()
        let sections = [
            section(
                key: "top",
                headerFrame: topSectionHeader,
                rows: [
                    .init(id: firstId, depth: 0, frame: middleRow)
                ]
            )
        ]
        let result = coordinator().resolvedItemDropTarget(
            sections: sections,
            touch: CGPoint(x: 30, y: 10),
            sourceSubtreeDepth: 0,
            dragGrabX: nil,
            dragGrabDepth: 0,
            fallbackBottomY: 500
        )

        #expect(result == .gap(ListDetailCollectionView.GapPosition(
            sectionKey: "top",
            beforeRowId: firstId,
            indent: 0
        )))
    }

    @Test func dragInBottomEmptySpaceTargetsLastSectionTail() {
        let firstSection = UUID()
        let secondSection = UUID()
        let sections = [
            section(
                key: "first",
                headerFrame: topSectionHeader,
                rows: [
                    .init(id: firstSection, depth: 0, frame: middleRow),
                    .init(id: UUID(), depth: 0, frame: lowerRow)
                ]
            ),
            section(
                key: "second",
                headerFrame: bottomSectionHeader,
                rows: [
                    .init(id: secondSection, depth: 0, frame: secondSectionRow)
                ]
            )
        ]
        let result = coordinator().resolvedItemDropTarget(
            sections: sections,
            touch: CGPoint(x: 30, y: 470),
            sourceSubtreeDepth: 0,
            dragGrabX: nil,
            dragGrabDepth: 0,
            fallbackBottomY: 500
        )

        #expect(result == .gap(ListDetailCollectionView.GapPosition(
            sectionKey: "second",
            beforeRowId: nil,
            indent: 0
        )))
    }

    @Test func dragIntoSectionWithNoRowsUsesSectionGap() {
        let sections = [
            section(
                key: "empty",
                headerFrame: topSectionHeader,
                rows: []
            ),
            section(
                key: "second",
                headerFrame: bottomSectionHeader,
                rows: []
            )
        ]
        let result = coordinator().resolvedItemDropTarget(
            sections: sections,
            touch: CGPoint(x: 30, y: 180),
            sourceSubtreeDepth: 0,
            dragGrabX: nil,
            dragGrabDepth: 0,
            fallbackBottomY: 320
        )

        #expect(result == .gap(ListDetailCollectionView.GapPosition(
            sectionKey: "empty",
            beforeRowId: nil,
            indent: 0
        )))
    }
}
