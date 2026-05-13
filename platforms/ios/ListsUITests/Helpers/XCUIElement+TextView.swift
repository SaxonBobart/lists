import XCTest

extension XCUIElement {
    /// Tap a normalized point inside the element. Wraps the
    /// `coordinate(withNormalizedOffset:)` dance into a single call.
    @MainActor
    func tap(atNormalized x: CGFloat, _ y: CGFloat) {
        coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }
}
