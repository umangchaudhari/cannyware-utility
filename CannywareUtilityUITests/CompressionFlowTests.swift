import XCTest

final class CompressionFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testEmptyStateAndPhotoPicker() throws {
        let app = XCUIApplication()
        app.launch()
        openCompressor(in: app)
        XCTAssertTrue(app.buttons["choosePhoto"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["compressPhoto"].isEnabled)
        screenshot("01-Choose-a-photo")
        app.buttons["choosePhoto"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["choosePhoto"].exists)
    }

    @MainActor
    func testCompressAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-photo"]
        app.launch()
        openCompressor(in: app)
        XCTAssertTrue(app.buttons["changePhoto"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["compressPhoto"].isEnabled)
        screenshot("02-Photo-ready")
        app.buttons["compressPhoto"].tap()
        let share = app.buttons["sharePhoto"]
        XCTAssertTrue(share.waitForExistence(timeout: 30))
        for _ in 0..<4 where !share.isHittable { app.swipeUp() }
        XCTAssertTrue(share.isHittable)
        screenshot("03-Compressed-result")
        share.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        screenshot("04-Share-JPEG")
    }

    @MainActor
    func testInvalidTargetAndPresetRecovery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-photo"]
        app.launch()
        openCompressor(in: app)
        XCTAssertTrue(app.buttons["changePhoto"].waitForExistence(timeout: 10))
        let input = app.textFields["targetSize"]
        reveal(input, in: app)
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "0")
        XCTAssertFalse(app.buttons["compressPhoto"].isEnabled)
        let preset = app.buttons["preset100000"]
        reveal(preset, in: app)
        preset.tap()
        XCTAssertTrue(app.buttons["compressPhoto"].isEnabled)
        app.buttons["compressPhoto"].tap()
        XCTAssertTrue(app.buttons["sharePhoto"].waitForExistence(timeout: 30))
    }

    @MainActor
    func testSaveToPhotoLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-photo"]
        app.launch()
        openCompressor(in: app)
        XCTAssertTrue(app.buttons["changePhoto"].waitForExistence(timeout: 10))
        app.buttons["compressPhoto"].tap()
        let save = app.buttons["savePhoto"]
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        let systemAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 3) {
            let allow = systemAlert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Allow'")).firstMatch
            XCTAssertTrue(allow.exists)
            allow.tap()
        }
        XCTAssertTrue(app.staticTexts["Saved to Photos"].waitForExistence(timeout: 10))
        XCTAssertFalse(save.isEnabled)
        screenshot("05-Saved-to-Photos")
    }

    @MainActor
    func testLandscapeLayout() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-photo"]
        app.launch()
        openCompressor(in: app)
        XCTAssertTrue(app.buttons["changePhoto"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["compressPhoto"].exists)
        screenshot("06-Landscape-layout")
    }

    @MainActor
    private func openCompressor(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["photoTools"].waitForExistence(timeout: 10))
        app.buttons["photoTools"].tap()
        app.buttons["openCompressor"].tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // isHittable can be true for partially clipped elements near the footer.
        for _ in 0..<5 {
            if element.isHittable && element.frame.maxY < app.frame.maxY - 160 { return }
            app.scrollViews.firstMatch.swipeUp()
        }
    }

    @MainActor
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
