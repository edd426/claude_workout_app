import XCTest

/// Screenshots of Settings, the Jefit import plan, the summary's records
/// "since 2026", and History (1.9.0, agent D), on the in-memory UI-test seed
/// plus a synthetic Jefit export. No real data.
///
/// Runs only when `TEST_RUNNER_SCREENSHOT_DIR` and
/// `TEST_RUNNER_SCREENSHOT_JEFIT_FIXTURE` (a synthetic CSV path) are set;
/// `TEST_RUNNER_SCREENSHOT_SUFFIX` names the pass (light, dark, ax5) and
/// `TEST_RUNNER_SCREENSHOT_CONTENT_SIZE` sets the text size.
final class SettingsHistoryShots: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!
    private var suffix = "light"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"], !dir.isEmpty,
              let fixture = env["SCREENSHOT_JEFIT_FIXTURE"], !fixture.isEmpty
        else {
            throw XCTSkip("Runs only with SCREENSHOT_DIR and SCREENSHOT_JEFIT_FIXTURE set")
        }
        outputDirectory = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        suffix = env["SCREENSHOT_SUFFIX"] ?? "light"
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-UITesting", "-seedTestData", "-UITestJefitFixturePath", fixture]
        if let size = env["SCREENSHOT_CONTENT_SIZE"], !size.isEmpty {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testShots() throws {
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        sleep(2)
        settingsAndJefit()
        workoutWithRecord()
        history()
    }

    // MARK: - Sections

    private func settingsAndJefit() {
        openSettings()
        sleep(1)
        snap("D70_settings")
        app.swipeUp()
        sleep(1)
        snap("D71_settings_backup")
        app.swipeUp()
        sleep(1)
        snap("D72_settings_bottom")

        let jefit = app.buttons["importJefitHistory"]
        scrollTo(jefit)
        jefit.safeTap()
        let plan = app.descendants(matching: .any)["jefitImportPlan"]
        if plan.waitForExistence(timeout: 20) {
            sleep(1)
            snap("D75_jefit_plan")
            app.swipeUp()
            sleep(1)
            snap("D76_jefit_plan_scrolled")
            app.buttons["jefitImportConfirm"].safeTap()
            if app.descendants(matching: .any)["jefitImportFinished"].waitForExistence(timeout: 20) {
                sleep(1)
                snap("D77_jefit_finished")
            }
            app.buttons.matching(NSPredicate(format: "label == 'Done'"))
                .allElementsBoundByIndex.last(where: { $0.isHittable })?.safeTap()
            sleep(1)
        } else {
            snap("D75_jefit_plan_missing")
        }
    }

    private func workoutWithRecord() {
        tab(app.tabBars.buttons["Today"].exists ? "Today" : "Home")
        let template = app.staticTexts["Push Day"]
        guard template.waitForExistence(timeout: 5) else { return }
        template.safeTap()
        let start = app.buttons["startWorkoutFromPreview"]
        guard start.waitForExistence(timeout: 5) else { return }
        start.safeTap()
        sleep(2)

        // Bench set 1 at 85 kg: above 80 kg, the best since 2026, and below
        // the synthetic 2019 set, the lifetime best.
        let weights = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'weight_'"))
        let completes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'completeSet_'"))
        if weights.count > 0 {
            let bench = weights.element(boundBy: 0)
            bench.safeTap()
            bench.clearText()
            bench.typeText("85")
            dismissKeyboard()
        }
        if completes.count > 0 { completes.element(boundBy: 0).safeTap() }
        sleep(1)
        skipRest()
        snap("D30_workout_set_logged")

        app.buttons["finishWorkout"].safeTap()
        sleep(1)
        // A finish confirmation for unlogged sets, if the build has one.
        for label in ["Finish Workout", "Finish", "Finish Anyway"] {
            let button = app.buttons[label]
            if button.exists, button.isHittable, !app.buttons["summaryDone"].exists {
                button.safeTap()
                break
            }
        }
        let done = app.buttons["summaryDone"]
        if done.waitForExistence(timeout: 10) {
            sleep(3)
            snap("D35_summary")
            app.swipeUp()
            sleep(1)
            snap("D36_summary_scrolled")
            scrollTo(done)
            done.safeTap()
            sleep(2)
        }
    }

    private func history() {
        tab("History")
        sleep(2)
        snap("D40_history_calendar")
        app.buttons["calendarPreviousMonth"].safeTap()
        sleep(1)
        snap("D41_history_calendar_previous_month")
        app.buttons["calendarNextMonth"].safeTap()
        sleep(1)

        let listSegment = app.buttons["List"]
        if listSegment.exists {
            listSegment.safeTap()
        } else {
            app.segmentedControls.buttons.element(boundBy: 1).safeTap()
        }
        sleep(1)
        snap("D43_history_list")

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow_'")).firstMatch
        let anyRow = row.exists ? row : app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow_'")).firstMatch
        if anyRow.waitForExistence(timeout: 5) {
            anyRow.safeTap()
            sleep(2)
            snap("D44_history_detail")
            app.swipeUp()
            sleep(1)
            snap("D45_history_detail_scrolled")
            let menu = app.buttons["workoutDetailMenu"]
            if menu.exists {
                menu.safeTap()
                sleep(1)
                snap("D46_history_detail_menu")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            }
        }
    }

    // MARK: - Helpers

    private func openSettings() {
        let tabButton = app.tabBars.buttons["Settings"]
        if tabButton.exists {
            tab("Settings")
        } else {
            app.buttons["settingsButton"].safeTap()
        }
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 5)
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        guard button.waitForExistence(timeout: 5) else { return }
        for _ in 0..<4 {
            button.safeTap()
            sleep(1)
            if button.isSelected { return }
        }
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let file = outputDirectory.appendingPathComponent("\(name)_\(suffix).png")
        try? shot.pngRepresentation.write(to: file)
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while swipes < maxSwipes, !(element.exists && element.isHittable) {
            app.swipeUp()
            swipes += 1
        }
    }

    private func dismissKeyboard() {
        for _ in 0..<3 where app.keyboards.count > 0 || app.keys.count > 0 {
            let done = app.buttons.matching(NSPredicate(format: "label == 'Done'"))
                .allElementsBoundByIndex
                .filter { $0.isHittable }
                .max(by: { $0.frame.minY < $1.frame.minY })
            if let done { done.safeTap() } else { app.swipeDown() }
            sleep(1)
        }
    }

    private func skipRest() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) { skip.safeTap() }
        sleep(1)
    }
}

private extension XCUIElement {
    func safeTap() {
        if exists, isHittable { tap() }
    }

    func clearText() {
        guard let value = value as? String, !value.isEmpty else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2))
    }
}
