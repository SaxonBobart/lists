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

    // MARK: - Remote images must not render or fetch

    /// A note body whose only image is a remote URL. With the `.asset` image
    /// providers pinned in `MarkdownBodyView`, the image resolves to a bundle
    /// asset lookup that misses, so it renders as nothing — never a network
    /// fetch. This snapshot locks that rendered result (text present, no broken
    /// image placeholder, no crash).
    ///
    /// Note: the *no-network* guarantee itself is structural, not asserted here —
    /// `AssetImageProvider`/`AssetInlineImageProvider` contain no `URLSession`
    /// code path at all, and the default network path uses a private session
    /// that can't be intercepted in a unit test. This test guards the render;
    /// the privacy property is guaranteed by construction.
    @MainActor
    func testRemoteImage_rendersNothing_iPhone16_Light() throws {
        let body = """
        Before image.

        ![remote](https://example.com/should-not-load.png)

        After image.
        """
        let view = ScrollView {
            MarkdownBodyView(body)
                .padding(16)
        }
        .background(Color(.systemBackground))
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 300)
        assertSnapshot(of: vc, as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testTable_iPhone16_Light() throws {
        assertSnapshot(of: tableHost(), as: .image(on: SnapshotEnvironment.iPhone16Light))
    }

    @MainActor
    func testTable_iPhone16_Dark() throws {
        assertSnapshot(
            of: tableHost(),
            as: .image(on: SnapshotEnvironment.iPhone16Light, traits: SnapshotEnvironment.darkTraits)
        )
    }

    @MainActor
    private func tableHost() -> UIHostingController<some View> {
        let body = """
        | Feature | Status | Owner |
        | :--- | :---: | ---: |
        | Portable Markdown | Ready | Lists |
        | Multiline cells<br>wrap naturally | In progress | Saxon |
        | Missing source cell | Safe |
        """
        let view = ScrollView {
            MarkdownBodyView(body)
                .padding(16)
        }
        .background(Color(.systemBackground))
        let vc = UIHostingController(rootView: view)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 320)
        return vc
    }
}
