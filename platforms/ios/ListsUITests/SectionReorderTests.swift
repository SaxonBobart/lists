import XCTest

@MainActor
final class SectionReorderTests: XCTestCase {

    func testReorderSectionsByDraggingHeader() {
        let app = XCUIApplication()
        app.launchClean()

        app.buttons["sidebar.list.personal"].tap()

        let healthCell = app.cells["list.section.\(XCUIApplication.SeedId.healthSection)"]
        let adminCell = app.cells["list.section.\(XCUIApplication.SeedId.adminSection)"]
        XCTAssert(healthCell.waitForExistence(timeout: 5))
        XCTAssert(adminCell.waitForExistence(timeout: 5))

        let initialHealthY = healthCell.frame.midY
        let initialAdminY = adminCell.frame.midY
        XCTAssertLessThan(initialHealthY, initialAdminY,
                          "Precondition: Health is above Admin initially")

        let start = adminCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = healthCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.8,
                    thenDragTo: end,
                    withVelocity: .slow,
                    thenHoldForDuration: 0.5)

        XCTAssert(adminCell.waitForExistence(timeout: 3))
        XCTAssert(healthCell.waitForExistence(timeout: 3))
        XCTAssertLessThan(adminCell.frame.midY, healthCell.frame.midY,
                          "Admin section should sit above Health after reorder")
    }
}
