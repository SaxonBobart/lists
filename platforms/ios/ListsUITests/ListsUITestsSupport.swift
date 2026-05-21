import XCTest

@MainActor
extension XCUIApplication {

    /// Reset on-disk Lists data and launch. Waits for the FAB so callers
    /// know the bootstrap completed and seed data is on screen.
    func launchClean() {
        launchArguments += ["--ui-testing-reset-data"]
        launch()
        XCTAssert(buttons["floating.add"].waitForExistence(timeout: 10),
                  "FAB never appeared — bootstrap may have failed")
    }

    enum ScrollDirection { case up, down }

    /// Bounded scroll-to-hittable. Never relies on XCUITest's implicit
    /// scroll-to-hittable, which fails inconsistently for SwiftUI Lists
    /// that lazily realize rows.
    @discardableResult
    func scrollToHittable(_ element: XCUIElement,
                          in container: XCUIElement? = nil,
                          maxScrolls: Int = 8,
                          direction: ScrollDirection = .down) -> Bool {
        let scrollSurface = container ?? collectionViews.firstMatch
        for _ in 0..<maxScrolls {
            if element.exists && element.isHittable { return true }
            switch direction {
            case .down: scrollSurface.swipeUp(velocity: .slow)
            case .up:   scrollSurface.swipeDown(velocity: .slow)
            }
        }
        return element.exists && element.isHittable
    }

    /// Press-and-drag using XCUICoordinate. Uses a non-zero initial press to
    /// trigger UICollectionView reorder; `thenHoldForDuration: 0` because that
    /// parameter is broken in XCUITest across recent iOS versions.
    func pressAndDrag(from start: XCUICoordinate,
                      to end: XCUICoordinate,
                      pressDuration: TimeInterval = 0.6,
                      velocity: XCUIGestureVelocity = .default) {
        start.press(forDuration: pressDuration,
                    thenDragTo: end,
                    withVelocity: velocity,
                    thenHoldForDuration: 0)
    }

    /// Commit a drag whose final hold is unreliable. Single-frame coordinate
    /// tap near the drop point gives UIKit the lift event it needs.
    func commitDrag(near coord: XCUICoordinate) {
        coord.press(forDuration: 0.05, thenDragTo: coord)
    }

    /// SwiftUI `.swipeActions` button — queried against the app root, not
    /// the cell. The action button lives in a sibling overlay window after
    /// the row is swiped open.
    func swipeActionButton(_ identifier: String) -> XCUIElement {
        return buttons[identifier]
    }

    /// Stable test ids — mirrors `SampleData.testIds`. UI tests run
    /// out-of-process and can't `@testable import Lists`, so the UUID
    /// strings are duplicated here. Any drift breaks tests in a way that
    /// points right at SampleData.
    enum SeedId {
        static let payPhoneBill        = "22222222-0000-0000-0000-000000000001"
        static let emailSarah          = "22222222-0000-0000-0000-000000000002"
        static let draftReply          = "22222222-0000-0000-0000-000000000003"
        static let submitTimesheet     = "22222222-0000-0000-0000-000000000004"
        static let run5km              = "22222222-0000-0000-0000-000000000005"
        static let stretchFirst        = "22222222-0000-0000-0000-000000000006"
        static let read30              = "22222222-0000-0000-0000-000000000007"
        static let bookDentist         = "22222222-0000-0000-0000-000000000008"
        static let confirmPrefTime     = "22222222-0000-0000-0000-000000000009"
        static let renewPassport       = "22222222-0000-0000-0000-00000000000A"
        static let callMum             = "22222222-0000-0000-0000-00000000000B"
        static let birthdayGiftAlex    = "22222222-0000-0000-0000-00000000000C"
        static let roadmapIdeas        = "22222222-0000-0000-0000-00000000000D"
        static let designSchema        = "22222222-0000-0000-0000-00000000000E"
        static let buildSync           = "22222222-0000-0000-0000-00000000000F"
        static let testSyncEndToEnd    = "22222222-0000-0000-0000-000000000010"
        static let buildEditor         = "22222222-0000-0000-0000-000000000011"

        /// Personal list section UUIDs (from SampleData).
        static let healthSection = "11111111-0000-0000-0000-000000000001"
        static let adminSection  = "11111111-0000-0000-0000-000000000002"
    }
}
