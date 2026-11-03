import XCTest

/// Idle-CPU probe for the active workout (#172, ui-standards UI-E5).
///
/// Starts a template workout, scrolls to the lower cards (the ones with notes
/// and a drift marker that used to pin the main thread), then touches nothing
/// for `PROBE_IDLE_SECONDS`. The host samples the app's CPU meanwhile, e.g.
/// with `ps -o %cpu -p <pid>`; marker files in `SCREENSHOT_DIR` say which
/// phase is running (`PROBE_TOP`, then `PROBE_SCROLLED`).
///
/// No UI queries run after the scroll: when the loop is present they time out
/// and would end the probe early, which is the bug itself.
///
/// Same environment as `ScreenshotTour` (seeded store, mock server); skipped
/// unless `SCREENSHOT_DIR` is set. `PROBE_TEMPLATE` picks the template
/// (default "Lower B").
final class WorkoutIdleProbe: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Idle probe runs only with SCREENSHOT_DIR set")
        }
        outputDirectory = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-serverURL", env["SCREENSHOT_SERVER_URL"] ?? "http://127.0.0.1:18765",
        ]
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Not Now", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testIdleAfterScrollingToLowerCards() throws {
        let env = ProcessInfo.processInfo.environment
        let templateName = env["PROBE_TEMPLATE"] ?? "Lower B"
        let idleSeconds = UInt32(env["PROBE_IDLE_SECONDS"] ?? "70") ?? 70

        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 120))
        sleep(3)
        let row = app.staticTexts[templateName]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealInHomeList(row)
        if row.isHittable { row.tap() }
        sleep(1)
        let start = app.buttons["startWorkoutFromPreview"]
        if start.waitForExistence(timeout: 5), start.isHittable { start.tap() }
        sleep(5)

        mark("PROBE_TOP")
        sleep(20)
        unmark("PROBE_TOP")

        // The evaluation's sequence before the loop (#172): log a set (the
        // rest bar appears), focus a weight field, dismiss, skip the rest.
        if env["PROBE_LOG_SET"] == "1" {
            logSetLikeTheEvaluation()
        }

        // On the any-order screen (1.9.0) the lower cards are collapsed;
        // open the last one from the strip so its notes and set rows render.
        // `isHittable` throws for a chip scrolled out of the strip, so swipe
        // the strip to its end and check the frame instead.
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stripChip_'"))
        if chips.count > 0 {
            let strip = app.scrollViews["exerciseStrip"]
            if strip.exists { strip.swipeLeft() }
            sleep(1)
            let last = chips.element(boundBy: chips.count - 1)
            if isOnScreen(last) { last.tap() }
            sleep(2)
        }
        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(2)
        snap("probe_scrolled")
        mark("PROBE_SCROLLED")
        sleep(idleSeconds)
        unmark("PROBE_SCROLLED")
    }

    private func logSetLikeTheEvaluation() {
        let complete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'completeSet_'"))
        if let first = complete.allElementsBoundByIndex.first(where: { isOnScreen($0) }) {
            first.tap()
            sleep(1)
        }
        let weights = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'weight_'"))
        if weights.count > 1 {
            let field = weights.element(boundBy: 1)
            if isOnScreen(field) { field.tap() }
            sleep(1)
            let done = app.buttons["Done"]
            if isOnScreen(done) { done.tap() }
            sleep(1)
        }
        for label in ["Skip rest", "Skip"] {
            let skip = app.buttons[label]
            if isOnScreen(skip) {
                skip.tap()
                break
            }
        }
        sleep(1)
    }

    private func isOnScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func mark(_ name: String) {
        try? Data().write(to: outputDirectory.appendingPathComponent(name))
    }

    private func unmark(_ name: String) {
        try? FileManager.default.removeItem(at: outputDirectory.appendingPathComponent(name))
    }

    private func snap(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    /// Home lists templates under its cards; drag the visible strip of the
    /// list until the row is hittable (same approach as `ScreenshotTour`).
    private func revealInHomeList(_ element: XCUIElement) {
        let list = app.collectionViews.firstMatch
        let tabTop = app.tabBars.firstMatch.frame.minY
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            guard list.exists else { app.swipeUp(); continue }
            let top = max(list.frame.minY, 0) + 4
            let bottom = min(list.frame.maxY, tabTop) - 4
            guard bottom - top > 16 else { app.swipeUp(); continue }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: list.frame.midX, dy: bottom))
                .press(forDuration: 0.05, thenDragTo:
                    origin.withOffset(CGVector(dx: list.frame.midX, dy: top)))
            sleep(1)
        }
    }
}
