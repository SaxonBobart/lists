import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class SmartListTileSnapshotTests: XCTestCase {

    @MainActor
    private func host(_ smartList: SmartList, count: Int) -> UIHostingController<some View> {
        let view = SmartListTile(smartList: smartList, count: count)
            .padding(16)
            .background(Color(.systemBackground))
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 100)
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
    func testUrgent_iPhone16_Light() throws {
        assertSnapshot(of: host(.urgent, count: 1), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testToday_iPhone16_A11yLarge() throws {
        assertSnapshot(
            of: host(.today, count: 5),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.a11yLargeTraits)
        )
    }
}
