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
                // Liquid Glass shadow dithering varies by up to two colour levels.
                precision: 0.998,
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

    @MainActor
    private func bottomRow() -> some View {
        Color(.systemBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomControlRow {
                    Image(systemName: "magnifyingglass")
                        .font(.title2).frame(width: 64, height: 64)
                        .glassEffect(.regular, in: Circle())
                    Spacer(minLength: 0)
                    FloatingAddButton(tint: .blue, action: {})
                }
            }
            .safeAreaPadding(.bottom, 34)
    }

    @MainActor
    func testBottomRow_Narrow() {
        assertSnapshot(of: bottomRow(), as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 320, height: 180),
            traits: SnapshotEnvironment.fixedLightTraits))
    }

    @MainActor
    func testBottomRow_Wide() {
        assertSnapshot(of: bottomRow(), as: .image(
            drawHierarchyInKeyWindow: true,
            layout: .fixed(width: 700, height: 180),
            traits: SnapshotEnvironment.fixedDarkTraits))
    }
}
