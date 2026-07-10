import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class FloatingAddButtonSnapshotTests: XCTestCase {
    @MainActor
    private func subject(tint: Color? = nil) -> some View {
        FloatingAddButton(tint: tint, action: {})
            .padding(20)
            .background(Color(.systemBackground))
    }

    @MainActor
    func testNeutral_Light() {
        assertSnapshot(
            of: subject(),
            as: .image(
                drawHierarchyInKeyWindow: true,
                layout: .fixed(width: 120, height: 120),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    @MainActor
    func testNeutral_Dark() {
        assertSnapshot(
            of: subject(),
            as: .image(
                drawHierarchyInKeyWindow: true,
                layout: .fixed(width: 120, height: 120),
                traits: SnapshotEnvironment.fixedDarkTraits
            )
        )
    }

    @MainActor
    func testTinted_Light() {
        assertSnapshot(
            of: subject(tint: .blue),
            as: .image(
                drawHierarchyInKeyWindow: true,
                layout: .fixed(width: 120, height: 120),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }
}
