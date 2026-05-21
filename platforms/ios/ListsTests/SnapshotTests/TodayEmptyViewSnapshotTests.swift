import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class TodayEmptyViewSnapshotTests: XCTestCase {

    @MainActor
    private func host() -> UIHostingController<some View> {
        let view = TodayEmptyView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        return vc
    }

    @MainActor
    func testEmpty_iPhone16_Light() throws {
        assertSnapshot(of: host(), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testEmpty_iPhone16_Dark() throws {
        assertSnapshot(
            of: host(),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }

    @MainActor
    func testEmpty_iPhoneSe_Light() throws {
        assertSnapshot(of: host(), as: .image(on: SnapshotEnvironment.iPhoneSeLight))
    }
}
