import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class FloatingAddButtonSnapshotTests: XCTestCase {

    @MainActor
    private func host(initial: Bool) -> UIHostingController<some View> {
        let view = SnapshotHostBool(initial: initial) { binding in
            FloatingAddButton(
                action: {},
                isInteracting: binding
            )
            .padding(20)
            .background(Color(.systemBackground))
        }
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
        return vc
    }

    @MainActor
    func testIdle_iPhone16_Light() throws {
        assertSnapshot(of: host(initial: false), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testIdle_iPhoneSe_Light() throws {
        assertSnapshot(of: host(initial: false), as: .image(on: SnapshotEnvironment.iPhoneSeLight))
    }

    @MainActor
    func testIdle_iPhone16_Dark() throws {
        assertSnapshot(
            of: host(initial: false),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }

    @MainActor
    func testInteracting_iPhone16_Light() throws {
        assertSnapshot(of: host(initial: true), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testInteracting_iPhoneSe_Light() throws {
        assertSnapshot(of: host(initial: true), as: .image(on: SnapshotEnvironment.iPhoneSeLight))
    }

    @MainActor
    func testInteracting_iPhone16_Dark() throws {
        assertSnapshot(
            of: host(initial: true),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }
}
