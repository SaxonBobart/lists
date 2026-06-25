import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

private struct TagInputHost: View {
    @State var tags: [String]
    var body: some View {
        TagInputView(tags: $tags)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
    }
}

final class TagInputViewSnapshotTests: XCTestCase {

    @MainActor
    private func host(tags: [String]) -> UIHostingController<some View> {
        let vc = UIHostingController(rootView: TagInputHost(tags: tags))
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 80)
        return vc
    }

    @MainActor
    func testEmpty_iPhone16_Light() throws {
        assertSnapshot(of: host(tags: []), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testEmpty_iPhoneSe_Light() throws {
        assertSnapshot(of: host(tags: []), as: .image(on: SnapshotEnvironment.iPhoneSeLight))
    }

    @MainActor
    func testEmpty_iPhone16_Dark() throws {
        assertSnapshot(
            of: host(tags: []),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }

    @MainActor
    func testWithTags_iPhone16_Light() throws {
        assertSnapshot(
            of: host(tags: ["work", "admin", "health"]),
            as: .image(on: SnapshotEnvironment.iPhone16Light)
        )
    }

    @MainActor
    func testWithTags_iPhoneSe_Light() throws {
        assertSnapshot(
            of: host(tags: ["work", "admin", "health"]),
            as: .image(on: SnapshotEnvironment.iPhoneSeLight)
        )
    }

    @MainActor
    func testWithTags_iPhone16_Dark() throws {
        assertSnapshot(
            of: host(tags: ["work", "admin", "health"]),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }

    @MainActor
    func testWithManyTags_iPhone16_A11yLarge() throws {
        assertSnapshot(
            of: host(tags: ["work", "admin", "health", "personal", "alarm", "finance"]),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.a11yLargeTraits)
        )
    }
}
