import XCTest

/// Screenshots of the 1.9.0 Today screen and the screens it opens, on
/// synthetic data (`-seedTodayDemo`), for review. Not a regression test:
/// skipped unless `SCREENSHOT_DIR` reaches the runner.
///
/// Run one pass per appearance or text size, e.g.
///
///     xcrun simctl ui <sim> appearance dark
///     TEST_RUNNER_SCREENSHOT_DIR=<dir> TEST_RUNNER_SCREENSHOT_SUFFIX=dark \
///       xcodebuild … test-without-building \
///       -only-testing:ClaudeLifterUITests/TodayScreenshotTour
///
/// `SCREENSHOT_CONTENT_SIZE` takes a `UIContentSizeCategory` raw value, such
/// as `UICTContentSizeCategoryAccessibilityXXXL` for AX5.
final class TodayScreenshotTour: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!
    private var suffix = "light"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Screenshot tour runs only with SCREENSHOT_DIR set")
        }
        outputDirectory = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        suffix = env["SCREENSHOT_SUFFIX"] ?? "light"
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-UITesting", "-seedTodayDemo"]
        if let size = env["SCREENSHOT_CONTENT_SIZE"], !size.isEmpty {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testTodayTour() throws {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30))
        // The seed lands after Today's first load; a tab round trip reloads.
        app.tabBars.buttons["History"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["todayStartWorkout"].waitForExistence(timeout: 10))
        sleep(2)
        snap("T01_today")
        app.swipeUp()
        sleep(1)
        snap("T02_today_scrolled")
        app.swipeUp()
        sleep(1)
        snap("T03_today_bottom")
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()

        let volume = app.buttons["weeklyVolumeCard"]
        scrollTo(volume)
        if volume.waitForExistence(timeout: 5) {
            volume.tap()
            sleep(2)
            snap("T04_volume_detail")
            app.swipeUp()
            sleep(1)
            snap("T05_volume_detail_scrolled")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        let needsYou = app.buttons["needsYouCard"]
        scrollTo(needsYou)
        if needsYou.waitForExistence(timeout: 5) {
            needsYou.tap()
            sleep(2)
            snap("T06_reports")
            let actions = app.buttons["reportActions"].firstMatch
            if actions.waitForExistence(timeout: 3) {
                actions.tap()
                sleep(1)
                snap("T07_report_menu")
                let delete = app.buttons["Delete"]
                if delete.waitForExistence(timeout: 3) {
                    delete.tap()
                    sleep(1)
                    snap("T08_report_delete_confirm")
                    // iOS 26+ shows no Cancel button in this dialog on
                    // iPhone; a tap outside it cancels.
                    let cancel = app.buttons["Cancel"]
                    if cancel.waitForExistence(timeout: 2), cancel.isHittable {
                        cancel.tap()
                    } else {
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
                    }
                    sleep(1)
                }
            }
            let close = app.buttons["closeReports"]
            if close.waitForExistence(timeout: 3) { close.tap() }
            // A sheet presented while another is still dismissing is
            // dropped; wait until the Reports sheet is gone.
            _ = waitForAbsence(of: close, timeout: 5)
            sleep(1)
        }

        let gear = app.buttons["settingsButton"]
        if gear.waitForExistence(timeout: 3) {
            gear.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 5)
            sleep(1)
            snap("T09_settings_sheet")
        }
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let file = outputDirectory.appendingPathComponent("\(name)_\(suffix).png")
        try? shot.pngRepresentation.write(to: file)
    }

    private func waitForAbsence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while swipes < maxSwipes, !(element.exists && element.isHittable) {
            app.swipeUp()
            swipes += 1
        }
    }
}
