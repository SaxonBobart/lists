import XCTest
import SnapshotTesting
@testable import Lists

final class SnapshotTestingPreflight: XCTestCase {
    func testSnapshotTestingIsLinked() throws {
        // Smoke test: if this compiles, the SnapshotTesting package is wired.
        let strategy: Snapshotting<UIView, UIImage> = .image
        XCTAssertNotNil(strategy.pathExtension)
    }
}
