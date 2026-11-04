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

    /// Settings is a sheet from Today's gear in 1.9.0; before that it was a
    /// tab. Either way in.
    private func openSettings() {
        let tab = app.tabBars.buttons["Settings"]
        if tab.waitForExistence(timeout: 3) {
            tab.tap()
        } else {
            let gear = app.buttons["settingsButton"]
            XCTAssertTrue(gear.waitForExistence(timeout: 5), "No Settings tab and no Today gear")
            gear.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testSettingsCanBeOpened() throws {
        openSettings()
    }

    func testWeightUnitPickerExists() throws {
        openSettings()
        XCTAssertTrue(app.pickers.count > 0 || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Weight Unit'")).firstMatch.exists)
    }

    func testAIModelPickerExists() throws {
        openSettings()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Model'")).firstMatch.waitForExistence(timeout: 5))
    }

    /// The server fields live in "Advanced", below the user's settings.
    func testAPIKeyFieldExists() throws {
        openSettings()
        // The only secure field on the screen; its label comes from the
        // prompt, so match by type rather than by title.
        let field = app.secureTextFields.firstMatch
        for _ in 0..<6 where !field.exists {
            app.swipeUp()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    /// The AI model rows are Buttons (UI-T4): one tap selects.
    func testAIModelRowSelectsOnOneTap() throws {
        openSettings()
        let sonnet = app.buttons["aiModel_claude-sonnet-4-6"]
        XCTAssertTrue(sonnet.waitForExistence(timeout: 5))
        sonnet.tap()
        XCTAssertTrue(sonnet.isSelected, "A single tap should select the model")
    }

    /// #171: Export Backup fired only on a press-and-hold, because a
    /// Form-wide tap gesture won the tap. One plain tap must open the share
    /// sheet. This regression had no test.
    func testExportBackupOpensShareSheetOnOneTap() throws {
        openSettings()
        let export = app.buttons["exportBackup"]
        for _ in 0..<6 where !(export.exists && export.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(export.isHittable, "Export Backup not reachable")

        export.tap()

        let shareSheet = app.otherElements["ActivityListView"]
        let wrapped = app.otherElements["backupShareSheet"]
        let appeared = shareSheet.waitForExistence(timeout: 10) || wrapped.exists
        XCTAssertTrue(appeared, "One tap on Export Backup should open the share sheet")
    }

    func testSettingsDismisses() throws {
        openSettings()
        let done = app.buttons["settingsDone"]
        if app.tabBars.buttons["Settings"].exists {
            // Tab layout: leave by tab.
            let home = app.tabBars.buttons["Today"].exists
                ? app.tabBars.buttons["Today"] : app.tabBars.buttons["Home"]
            home.tap()
        } else {
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
    }
}
