import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class ListIconGlyphSnapshotTests: XCTestCase {
    @MainActor
    func testSFSymbolWhite() throws {
        let view = ListIconGlyph(icon: "briefcase.fill", size: 28, color: .white)
            .padding(20)
            .background(Color.orange)
        assertSnapshot(
            of: view,
            as: .image(
                layout: .fixed(width: 100, height: 100),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    @MainActor
    func testEmojiGlyph() throws {
        let view = ListIconGlyph(icon: "🎯", size: 28)
            .padding(20)
            .background(Color.gray.opacity(0.2))
        assertSnapshot(
            of: view,
            as: .image(
                layout: .fixed(width: 100, height: 100),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }

    @MainActor
    func testEveryListColor() throws {
        // Renders all 12 ListColor cases in a grid so a single PNG covers them.
        let colors = ItemList.ListColor.allCases
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(60), spacing: 8), count: 4),
                              spacing: 8) {
            ForEach(colors, id: \.self) { c in
                ZStack {
                    Circle()
                        .fill(ListsTokens.listColor(c))
                        .frame(width: 56, height: 56)
                    ListIconGlyph(icon: "list.bullet", size: 22, color: .white)
                }
            }
        }
        .padding(20)
        assertSnapshot(
            of: grid.frame(width: 320, height: 320),
            as: .image(
                layout: .fixed(width: 320, height: 320),
                traits: SnapshotEnvironment.fixedLightTraits
            )
        )
    }
}
