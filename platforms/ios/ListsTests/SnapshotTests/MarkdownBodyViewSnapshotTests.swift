import XCTest
import SwiftUI
import SnapshotTesting
@testable import Lists

final class MarkdownBodyViewSnapshotTests: XCTestCase {

    private static let sample = """
    # Heading one

    A paragraph with **bold** and *italic* and a [link](https://example.com).

    ## Subheading

    - Bullet one
    - Bullet two
      - Nested bullet

    1. Ordered item
    2. Another ordered item

    - [ ] Unchecked task
    - [x] Completed task

    `inline code` and a fenced block:

    ```swift
    let x = 1
    print(x)
    ```
    """

    @MainActor
    private func host() -> UIHostingController<some View> {
        let view = ScrollView {
            MarkdownBodyView(Self.sample)
                .padding(16)
        }
        .background(Color(.systemBackground))
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        return vc
    }

    @MainActor
    func testSample_iPhone16_Light() throws {
        assertSnapshot(of: host(), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testSample_iPhone16_Dark() throws {
        assertSnapshot(
            of: host(),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }

    @MainActor
    func testSample_iPhone16_A11yLarge() throws {
        assertSnapshot(
            of: host(),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.a11yLargeTraits)
        )
    }
}
