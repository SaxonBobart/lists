import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class SmartListTileSnapshotTests: XCTestCase {

    @MainActor
    private func host(
        _ smartList: SmartList,
        count: Int,
        width: CGFloat = 393,
        height: CGFloat = 100,
        outerPadding: CGFloat = 16
    ) -> UIHostingController<AnyView> {
        let view = AnyView(
            SmartListTile(smartList: smartList, count: count)
                .padding(outerPadding)
                .background(Color(.systemBackground))
        )
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return vc
    }

    @MainActor
    func testToday_iPhone16_Light() throws {
        assertSnapshot(of: host(.today, count: 5), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testScheduled_iPhone16_Light() throws {
        assertSnapshot(of: host(.scheduled, count: 12), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testScheduledGridColumn_iPhone16_Light() throws {
        let view = SmartListTile(smartList: .scheduled, count: 15)
            .background(Color(.systemBackground))

        assertSnapshot(
            of: view,
            as: .image(
                layout: .fixed(width: 181, height: 60),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    @MainActor
    func testAll_iPhone16_Light() throws {
        assertSnapshot(of: host(.all, count: 42), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testCompleted_iPhone16_Light() throws {
        assertSnapshot(of: host(.completed, count: 8), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testFlagged_iPhone16_Light() throws {
        assertSnapshot(of: host(.flagged, count: 3), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testAlarms_iPhone16_Light() throws {
        assertSnapshot(of: host(.alarms, count: 1), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testToday_iPhone16_A11yLarge() throws {
        assertSnapshot(
            of: host(.today, count: 5),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.a11yLargeTraits)
        )
    }
}
