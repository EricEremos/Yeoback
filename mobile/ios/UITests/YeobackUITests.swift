import XCTest

final class YeobackUITests: XCTestCase {
    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFixtureReviewCancelAndCleanup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["select-matching"].waitForExistence(timeout: 30))
        screenshot("iPhone-Light-Inventory")
        app.buttons["select-matching"].tap()
        XCTAssertTrue(app.staticTexts["selection-count"].label.contains("15 selected"))
        app.buttons["review-selection"].tap()
        XCTAssertTrue(app.staticTexts["review-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["review-count"].label.contains("15 files"))
        XCTAssertFalse(app.buttons["confirm-delete"].isEnabled)
        screenshot("iPhone-Review-Permanent-Deletion")
        app.buttons["cancel-review"].tap()
        XCTAssertTrue(app.staticTexts["selection-count"].label.contains("15 selected"))
        app.buttons["review-selection"].tap()
        let toggle = app.buttons["acknowledge-deletion"]
        for _ in 0..<12 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Acknowledged")
        XCTAssertTrue(app.buttons["confirm-delete"].isEnabled)
        app.buttons["confirm-delete"].tap()
        XCTAssertTrue(app.staticTexts["cleanup-summary"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["cleanup-summary"].label.contains("15 deleted"))
        screenshot("iPhone-Cleanup-Results")
    }
    func testDarkAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "-appearance", "Dark"]
        app.launch()
        XCTAssertTrue(app.buttons["select-matching"].waitForExistence(timeout: 30))
        screenshot("iPhone-Dark-Inventory")
    }
}
