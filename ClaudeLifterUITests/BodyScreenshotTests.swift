import XCTest

/// Body-tab screenshots (1.9.0) on synthetic data, never anyone's real
/// numbers: the app seeds its in-memory store itself (`-UITesting
/// -seedBodyData`, DEBUG only). A capture tool, not a regression test, so it
/// is skipped unless `BODY_SCREENSHOT_DIR` reaches the runner:
///
///     TEST_RUNNER_BODY_SCREENSHOT_DIR=<host dir> \
///     TEST_RUNNER_BODY_SCREENSHOT_SUFFIX=light|dark|ax5 \
///     [TEST_RUNNER_BODY_SCREENSHOT_CONTENT_SIZE=UICTContentSizeCategoryAccessibilityXXXL] \
///     xcodebuild … test-without-building \
///         -only-testing:ClaudeLifterUITests/BodyScreenshotTests
///
/// Set the appearance first with `xcrun simctl ui <udid> appearance dark`.
final class BodyScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var directory: URL!
    private var suffix = "light"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["BODY_SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Body screenshots run only with BODY_SCREENSHOT_DIR set")
        }
        directory = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suffix = env["BODY_SCREENSHOT_SUFFIX"] ?? "light"
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-seedBodyData"]
        if let size = env["BODY_SCREENSHOT_CONTENT_SIZE"], !size.isEmpty {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testBodyTab() throws {
        app.launch()
        let tab = app.tabBars.buttons["Body"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "No Body tab")
        tab.tap()
        XCTAssertTrue(app.buttons["bodyLogWeight"].waitForExistence(timeout: 20))
        sleep(2)
        snap("B01_body_top")

        // Swipe from the lower part of the screen: a swipe from the middle
        // starts on the chart and the scroll did not move on the first try.
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        lower.press(forDuration: 0.05, thenDragTo: upper)
        sleep(1)
        snap("B02_body_middle")
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        snap("B03_body_bottom")

        logWaistSheet()
        heightSheet()
        addMedicationSheet()
        oneTapLog()
        doseSheet()
        detailScreen()
    }

    // MARK: - Sheets and screens

    private func logWaistSheet() {
        guard reveal(app.buttons["bodyLogWaist"]) else { return }
        app.buttons["bodyLogWaist"].tap()
        guard app.textFields["waistField"].waitForExistence(timeout: 5) else { return }
        sleep(1)
        snap("B10_log_waist_sheet")
        tapCancel()
    }

    private func heightSheet() {
        guard reveal(app.buttons["bodyHeightRow"]) else { return }
        app.buttons["bodyHeightRow"].tap()
        guard app.buttons["saveHeight"].waitForExistence(timeout: 5) else { return }
        sleep(1)
        snap("B11_height_sheet")
        tapCancel()
    }

    private func addMedicationSheet() {
        let add = app.buttons["bodyAddMedication"]
        guard reveal(add) else { return }
        add.tap()
        let name = app.textFields["medicationNameField"]
        guard name.waitForExistence(timeout: 5) else { return }
        name.typeText("Medication D")
        choose(app.buttons["medicationUnitPicker"], option: "mL")
        choose(app.buttons["concentrationModePicker"], option: "Mixed vial")
        type("0.5", into: "medicationField-Usual dose")
        type("10", into: "medicationField-Amount in the vial")
        type("2", into: "medicationField-Liquid added")
        sleep(1)
        snap("B12_add_medication_sheet")
        tapCancel()
    }

    private func oneTapLog() {
        let log = app.buttons["logDose-Medication B"]
        guard reveal(log) else { return }
        log.tap()
        _ = app.buttons["undoDose-Medication B"].waitForExistence(timeout: 5)
        snap("B13_after_one_tap_log")
    }

    private func doseSheet() {
        let menu = app.buttons["medicationMenu-Medication A"]
        guard reveal(menu) else { return }
        menu.tap()
        let item = app.buttons["Log a different dose…"]
        guard item.waitForExistence(timeout: 5) else { return }
        item.tap()
        guard app.textFields["doseAmountField"].waitForExistence(timeout: 5) else { return }
        sleep(1)
        snap("B14_log_dose_sheet")
        tapCancel()
    }

    private func detailScreen() {
        let row = app.buttons["medicationRow-Medication A"]
        guard reveal(row) else { return }
        row.tap()
        guard app.buttons["editMedication"].waitForExistence(timeout: 5) else { return }
        sleep(1)
        snap("B15_medication_detail")
        app.swipeUp()
        snap("B16_medication_detail_scrolled")
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // MARK: - Helpers

    /// Scrolls the Body screen until `element` is hittable.
    private func reveal(_ element: XCUIElement) -> Bool {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        for _ in 0..<8 {
            if element.exists, element.isHittable { return true }
            app.swipeDown()
        }
        XCTFail("Could not reach \(element)")
        return false
    }

    private func choose(_ picker: XCUIElement, option: String) {
        guard picker.waitForExistence(timeout: 3) else { return }
        picker.tap()
        let item = app.buttons[option].firstMatch
        if item.waitForExistence(timeout: 3) { item.tap() }
    }

    private func type(_ text: String, into identifier: String) {
        let field = app.textFields[identifier]
        for _ in 0..<3 where !field.isHittable { app.swipeUp() }
        guard field.waitForExistence(timeout: 3) else { return }
        field.tap()
        field.typeText(text)
    }

    private func tapCancel() {
        let cancel = app.navigationBars.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        sleep(1)
    }

    private func snap(_ name: String) {
        let url = directory.appendingPathComponent("\(name)_\(suffix).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
