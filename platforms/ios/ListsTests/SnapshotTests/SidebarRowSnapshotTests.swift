import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class SidebarRowSnapshotTests: XCTestCase {

    @MainActor
    private func host<V: View>(_ view: V) -> UIHostingController<some View> {
        let wrapped = view
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        let vc = UIHostingController(rootView: wrapped)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 56)
        return vc
    }

    @MainActor
    func testRegularList_iPhone16_Light() throws {
        let row = SidebarRow(
            icon: "briefcase.fill",
            hue: ListsTokens.listColor(.orange),
            label: "Work"
        )
        assertSnapshot(of: host(row), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testWithCount_iPhone16_Light() throws {
        let row = SidebarRow(
            icon: "person.fill",
            hue: ListsTokens.listColor(.purple),
            label: "Personal",
            count: 12
        )
        assertSnapshot(of: host(row), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testWithoutCount_iPhone16_Light() throws {
        let row = SidebarRow(
            icon: "tray.fill",
            hue: ListsTokens.listColor(.blue),
            label: "Inbox",
            count: nil
        )
        assertSnapshot(of: host(row), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testWithIndent_iPhone16_Light() throws {
        let row = SidebarRow(
            icon: "hammer.fill",
            hue: ListsTokens.listColor(.teal),
            label: "Side App",
            count: 4,
            indent: 1
        )
        assertSnapshot(of: host(row), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testCircleShape_iPhone16_Light() throws {
        let row = SidebarRow(
            icon: "tag.fill",
            hue: ListsTokens.tagAccent,
            label: "Tags",
            count: 9,
            iconShape: .circle
        )
        assertSnapshot(of: host(row), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testRegularList_iPhone16_Dark() throws {
        let row = SidebarRow(
            icon: "briefcase.fill",
            hue: ListsTokens.listColor(.orange),
            label: "Work",
            count: 7
        )
        assertSnapshot(
            of: host(row),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }
}
