import XCTest

final class SettingsTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func openSettings() {
        app.tabBars.buttons["Settings"].tap()
    }

    func testSettingsCanBeOpened() throws {
        openSettings()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testWeightUnitPickerExists() throws {
        openSettings()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.pickers.count > 0 || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Weight Unit'")).firstMatch.exists)
    }

    func testAIModelPickerExists() throws {
        openSettings()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Model'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testAPIKeyFieldExists() throws {
        openSettings()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'API'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testSettingsDismisses() throws {
        openSettings()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        // Navigate back to Home tab
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 5))
    }
}
