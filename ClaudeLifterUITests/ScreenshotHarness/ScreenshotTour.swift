import XCTest

/// Screenshot tour of every screen, for UX review (not a regression test).
///
/// Skipped unless `SCREENSHOT_DIR` reaches the runner, so it never runs in
/// the ordinary UI suite. Driven by `run_screenshot_tour.sh` in this folder.
/// Start `mock_functions_server.py` first: it serves the inbox, insights and
/// Coach replies. The driver seeds the store from a mirror snapshot with
/// `seed_store_from_snapshot.py` and runs the tour once per appearance or
/// text size.
///
/// The app is launched WITHOUT `-UITesting`. The in-memory test store skips
/// the bundled-catalog import, so the library would be empty and history
/// would have no exercises to point at. Instead the tour uses the
/// simulator's real store. The server URL comes from a launch-argument
/// UserDefaults override that points at the local mock. Never run this
/// against production: a real push from a simulator replaces the cloud
/// mirror.
///
/// Environment (pass with the `TEST_RUNNER_` prefix to xcodebuild):
/// - `SCREENSHOT_DIR`: absolute host path; PNGs are written there directly.
/// - `SCREENSHOT_SUFFIX`: appended to every file name (`light`, `dark`, `ax5`).
/// - `SCREENSHOT_SERVER_URL`: defaults to `http://127.0.0.1:18765`.
/// - `SCREENSHOT_CONTENT_SIZE`: a `UIContentSizeCategory` raw value, e.g.
///   `UICTContentSizeCategoryAccessibilityXXXL`.
final class ScreenshotTour: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!
    private var suffix = "light"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Screenshot tour runs only with SCREENSHOT_DIR set")
        }
        outputDirectory = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        suffix = env["SCREENSHOT_SUFFIX"] ?? "light"
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchArguments += [
            "-serverURL", env["SCREENSHOT_SERVER_URL"] ?? "http://127.0.0.1:18765",
        ]
        if let size = env["SCREENSHOT_CONTENT_SIZE"], !size.isEmpty {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Not Now", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.safeTap()
                    return true
                }
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    // MARK: - Setup

    /// One-time: first launch, so the app creates its store and imports the
    /// bundled exercise catalog. `run_screenshot_tour.sh restore` then closes
    /// the app and seeds the store with `seed_store_from_snapshot.py`.
    /// Runs only when `SCREENSHOT_RESTORE=1`.
    ///
    /// Settings → Restore from Cloud would be the natural path, but no Form
    /// row button in Settings responds to a tap on the iOS 26.5 simulator
    /// (Restore, Export and Import all do nothing), so the harness cannot use
    /// it. `test06_settings` records that on every run.
    func test00_firstLaunch() throws {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_RESTORE"] == "1" else {
            throw XCTSkip("First-launch setup runs only with SCREENSHOT_RESTORE=1")
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 600))
        // The catalog import and the first sync (insights) run after launch.
        sleep(20)
        tab("Exercises")
        sleep(5)
        tab("Today")
        sleep(5)
    }

    // MARK: - Tour

    /// One test, fixed order. The scheme randomises test order, and the
    /// workout section must run last because it finishes a workout.
    /// `SCREENSHOT_SECTIONS` (comma-separated) limits which sections run.
    func test01_tour() throws {
        let requested = ProcessInfo.processInfo.environment["SCREENSHOT_SECTIONS"]
            .flatMap { $0.isEmpty ? nil : Set($0.split(separator: ",").map(String.init)) }
        func wants(_ name: String) -> Bool { requested?.contains(name) ?? true }
        if wants("home") { tourHome() }
        if wants("library") { tourLibrary() }
        if wants("history") { tourHistory() }
        if wants("coach") { tourCoach() }
        if wants("settings") { tourSettings() }
        if wants("workout") {
            tourActiveWorkout()
            tourWorkoutScroll()
        }
        if requested?.contains("workoutLiveResize") == true { tourWorkoutLiveResize() }
    }

    // MARK: - Home

    private func tourHome() {
        launchToHome()
        snap("01_home_idle")
        app.swipeUp()
        snap("02_home_scrolled")
        app.swipeDown()
        app.swipeDown()

        // The card's identifier overrides the button's, so match the label.
        let review = app.buttons["Review Changes"]
        if review.waitForExistence(timeout: 5) {
            review.safeTap()
            sleep(2)
            snap("03_pending_changes")
            app.swipeUp()
            snap("04_pending_changes_scrolled")
            tapIfExists(app.buttons["pendingChangesDone"])
            sleep(2)
        }

        let reports = app.buttons["openReportsCard"]
        if reports.waitForExistence(timeout: 3) {
            reports.safeTap()
            sleep(1)
            snap("05_reports_list")
            let filter = app.buttons["reportStatusFilter"]
            if filter.waitForExistence(timeout: 3) {
                filter.safeTap()
                snap("06_reports_filter_menu")
                tapIfExists(app.buttons["All"])
                sleep(1)
                snap("07_reports_all")
            }
            let firstCell = app.cells.firstMatch
            if firstCell.waitForExistence(timeout: 3) {
                firstCell.swipeLeft()
                snap("08_reports_swipe_actions")
                firstCell.swipeRight()
            }
            dismissSheet()
        }

        let flag = app.buttons["reportFromHome"]
        if flag.waitForExistence(timeout: 3) {
            flag.safeTap()
            sleep(1)
            snap("09_report_sheet_from_home")
            tapIfExists(app.buttons["Cancel"])
            sleep(1)
        }

        let log = app.buttons["Log"]
        if log.waitForExistence(timeout: 3) {
            log.safeTap()
            sleep(1)
            snap("10_body_weight_log_sheet")
            tapIfExists(app.buttons["Cancel"])
            sleep(1)
        }

        let upperA = app.staticTexts["Upper A"]
        revealInHomeList(upperA)
        snap("15_home_list_scrolled_to_upper_a")
        upperA.safeTap()
        if app.buttons["startWorkoutFromPreview"].waitForExistence(timeout: 3) {
            sleep(1)
            snap("11_template_preview_upper_a")
            app.swipeUp()
            snap("12_template_preview_upper_a_scrolled")
            tapIfExists(app.buttons["Edit"])
            sleep(1)
            snap("13_template_editor")
            tapIfExists(app.buttons["Cancel"])
            sleep(1)
            app.navigationBars.buttons.firstMatch.safeTap()
        }

        app.swipeUp()
        app.swipeUp()
        let manage = app.buttons["Manage Templates"]
        if manage.waitForExistence(timeout: 3) {
            manage.safeTap()
            sleep(1)
            snap("14_manage_templates")
            app.navigationBars.buttons.firstMatch.safeTap()
        }
    }

    // MARK: - Active workout


    /// Ordered so every UI query happens before the cards further down are
    /// scrolled into view: once the note-carrying cards render, accessibility
    /// queries on this screen time out on the iOS 26.5 simulator. Scroll
    /// screenshots therefore come last, with no queries after them.
    private func tourActiveWorkout() {
        launchToHome()
        let lowerA = app.staticTexts["Lower A"]
        XCTAssertTrue(lowerA.waitForExistence(timeout: 5))
        revealInHomeList(lowerA)
        lowerA.safeTap()
        sleep(1)
        snap("20_template_preview_lower_a")
        app.buttons["startWorkoutFromPreview"].safeTap()
        sleep(3)
        snap("21_workout_start")

        let completes = setButtons("completeSet_")
        if completes.count > 0 {
            completes.element(boundBy: 0).safeTap()
            sleep(1)
            snap("22_workout_set_logged_rest_timer")
        }

        let weights = setButtons("weight_")
        if weights.count > 1 {
            weights.element(boundBy: 1).safeTap()
            sleep(1)
            snap("23_workout_keyboard_weight")
            dismissKeyboard()
            sleep(1)
        }
        // The rest ring animates every second, which starves UI queries.
        skipRest()

        if let menu = hittableExerciseMenu() {
            menu.safeTap()
            sleep(1)
            snap("28_workout_exercise_menu")
            let note = app.buttons["editExerciseNotes"]
            if note.waitForExistence(timeout: 2) {
                note.safeTap()
                sleep(2)
                snap("29_workout_note_editor")
                tapIfExists(app.buttons["Cancel"])
                sleep(1)
            }
        }
        if let menu = hittableExerciseMenu() {
            menu.safeTap()
            let report = app.buttons["reportExercise"]
            if report.waitForExistence(timeout: 2) {
                report.safeTap()
                sleep(2)
                snap("30_workout_report_sheet")
                tapIfExists(app.buttons["Cancel"])
                sleep(1)
            }
        }
        dismissKeyboard()

        // A fourth squat set: a set-count change, so the summary has a
        // template decision to show (the #150 pile-up).
        let addSet = app.buttons.matching(NSPredicate(format: "label == 'Add Set'"))
            .allElementsBoundByIndex.first(where: { $0.isHittable })
        addSet?.safeTap()
        sleep(1)
        snap("25_workout_added_set")

        tapIfExists(app.buttons["finishWorkout"])
        sleep(4)
        snap("35_summary")
        let reviewChanges = app.buttons["reviewTemplateChanges"]
        if reviewChanges.waitForExistence(timeout: 5) {
            scrollTo(reviewChanges)
            snap("36_summary_template_prompt")
            reviewChanges.safeTap()
            sleep(1)
            snap("37_summary_template_review")
        }
        app.swipeUp()
        sleep(1)
        snap("38_summary_bottom")
        let done = app.buttons["summaryDone"]
        scrollTo(done)
        tapIfExists(done)
        sleep(2)
        snap("39_home_after_workout")

        tourAddExerciseInEmptyWorkout()
        tourExitDialog()
    }

    /// The Exit dialog needs a logged set. On iOS 26 it is a popover whose
    /// cancel ("Keep Going") is not a button and does not dismiss on a
    /// title tap, so this leaves via "Discard" and must come last.
    private func tourExitDialog() {
        launchToHome()
        let upperB = app.staticTexts["Upper B"]
        guard upperB.waitForExistence(timeout: 5) else { return }
        revealInHomeList(upperB)
        upperB.safeTap()
        sleep(1)
        app.buttons["startWorkoutFromPreview"].safeTap()
        sleep(3)
        setButtons("completeSet_").firstMatch.safeTap()
        sleep(1)
        skipRest()
        tapIfExists(app.buttons["cancelWorkout"])
        sleep(1)
        snap("34_workout_exit_dialog")
        tapIfExists(app.buttons["Discard — don't save"])
        sleep(1)
    }

    /// The add-exercise picker, from an empty workout so nothing needs
    /// scrolling. Also the only "swap" path the app has today.
    private func tourAddExerciseInEmptyWorkout() {
        let start = app.buttons["Start Empty Workout"]
        revealInHomeList(start)
        start.safeTap()
        sleep(3)
        let add = app.buttons["addExerciseToWorkout"]
        guard add.waitForExistence(timeout: 5) else { return }
        add.safeTap()
        sleep(2)
        snap("31_workout_add_exercise_picker")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            for _ in 0..<3 where !app.isSoftwareKeyboardVisible {
                search.safeTap()
                sleep(1)
            }
            guard app.isSoftwareKeyboardVisible else { return }
            search.typeText("leg press")
            sleep(2)
            snap("32_workout_add_exercise_search")
            let row = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Leg Press'")
            ).firstMatch
            if row.waitForExistence(timeout: 3) {
                row.safeTap()
                sleep(3)
                snap("33_workout_added_exercise")
            } else {
                tapIfExists(app.buttons["Cancel"])
            }
        }
        // Leave it as a discarded empty workout.
        tapIfExists(app.buttons["cancelWorkout"])
        sleep(1)
        tapIfExists(app.buttons["Discard — don't save"])
        sleep(1)
    }

    /// The workout and summary at AX5. At that size Home's cards hide every
    /// template row, so the workout is started at the default size; the
    /// driver then flips the simulator's text size live (`simctl ui
    /// content_size`) when it sees the marker file.
    private func tourWorkoutLiveResize() {
        launchToHome()
        let lowerA = app.staticTexts["Lower A"]
        guard lowerA.waitForExistence(timeout: 5) else { return }
        revealInHomeList(lowerA)
        lowerA.safeTap()
        sleep(1)
        app.buttons["startWorkoutFromPreview"].safeTap()
        sleep(3)
        setButtons("completeSet_").firstMatch.safeTap()
        sleep(1)
        skipRest()
        let marker = outputDirectory.appendingPathComponent("READY_FOR_RESIZE")
        try? Data().write(to: marker)
        sleep(45)
        snap("21_workout_start")
        app.swipeUp()
        sleep(2)
        snap("21c_workout_stacked_rows")
        tapIfExists(app.buttons["finishWorkout"])
        sleep(4)
        snap("35_summary")
        try? FileManager.default.removeItem(at: marker)
    }

    /// Scroll screenshots of a full template workout. Runs last because
    /// queries after this point time out (see `tourActiveWorkout`).
    private func tourWorkoutScroll() {
        launchToHome()
        let lowerB = app.staticTexts["Lower B"]
        guard lowerB.waitForExistence(timeout: 5) else { return }
        revealInHomeList(lowerB)
        lowerB.safeTap()
        sleep(1)
        app.buttons["startWorkoutFromPreview"].safeTap()
        sleep(3)
        snap("26_workout_lower_b_start")
        app.swipeUp()
        sleep(2)
        snap("24_workout_scrolled_mid")
        app.swipeUp()
        sleep(2)
        snap("27_workout_bottom")
    }


    // MARK: - History and charts

    private func tourHistory() {
        launchToHome()
        tab("History")
        sleep(2)
        snap("40_history_calendar_current_month")
        // The month chevrons carry no accessibility label, so tap the left
        // one by position, level with the month title.
        let monthTitle = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '^[A-Z][a-z]+ 20[0-9][0-9]$'")
        ).firstMatch
        if monthTitle.waitForExistence(timeout: 3) {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 30, dy: monthTitle.frame.midY))
                .tap()
            sleep(2)
            snap("41_history_calendar_october")
            let day = app.staticTexts["8"]
            if day.exists {
                day.safeTap()
                sleep(1)
                app.swipeUp()
                snap("42_history_calendar_day_selected")
                app.swipeDown()
            }
        }

        let segments = app.segmentedControls.firstMatch.buttons
        if segments.count > 1 {
            segments.element(boundBy: 1).safeTap()
            sleep(2)
            snap("43_history_list")
            let row = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'historyRow_'")
            ).element(boundBy: 1)
            let fallback = app.cells.element(boundBy: 1)
            let target = row.exists ? row : fallback
            if target.exists {
                target.safeTap()
                sleep(2)
                snap("44_history_workout_detail")
                if app.buttons["Edit"].exists {
                    app.buttons["Edit"].safeTap()
                    sleep(1)
                    snap("45_history_workout_detail_editing")
                    tapIfExists(app.buttons["Cancel"])
                    sleep(1)
                }
                app.navigationBars.buttons.firstMatch.safeTap()
                sleep(1)
            }
            segments.element(boundBy: 0).safeTap()
        }

        let chartsLink = app.navigationBars["History"].buttons.firstMatch
        if chartsLink.exists {
            chartsLink.safeTap()
            sleep(3)
            snap("46_charts")
            app.swipeUp()
            sleep(1)
            snap("47_charts_scrolled")
            app.swipeUp()
            sleep(1)
            snap("48_charts_bottom")
        }
    }

    // MARK: - Exercise library

    private func tourLibrary() {
        launchToHome()
        tab("Exercises")
        sleep(3)
        snap("50_library")

        let equipment = app.buttons["Equipment"]
        if equipment.waitForExistence(timeout: 3) {
            equipment.safeTap()
            sleep(1)
            snap("51_library_equipment_menu")
            let machine = app.buttons["Machine"]
            if machine.exists {
                machine.safeTap()
                sleep(2)
                snap("52_library_filter_machine")
            } else {
                app.safeTap()
            }
        }

        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.safeTap()
            search.typeText("curl")
            sleep(2)
            snap("53_library_filter_plus_search")
            tapIfExists(app.buttons["Search"])
            tapIfExists(app.buttons["Cancel"])
            sleep(1)
        }
        tapIfExists(app.buttons["Clear All"])
        sleep(1)

        if search.waitForExistence(timeout: 3) {
            search.safeTap()
            tapIfExists(app.buttons["Clear text"])
            search.clearAndTypeText("seated leg curl")
            sleep(2)
            let row = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Seated Leg Curl'")
            ).firstMatch
            if row.waitForExistence(timeout: 3) {
                row.safeTap()
                sleep(3)
                snap("54_exercise_detail")
                app.swipeUp()
                sleep(1)
                snap("55_exercise_detail_scrolled")
                app.swipeUp()
                sleep(1)
                snap("56_exercise_detail_bottom")
            }
        }
    }

    // MARK: - Coach

    private func tourCoach() {
        launchToHome()
        tab("Coach")
        sleep(2)
        snap("60_coach_empty")
        let input = app.textFields["chatMessageInput"].exists
            ? app.textFields["chatMessageInput"] : app.textViews["chatMessageInput"]
        if input.waitForExistence(timeout: 5) {
            input.safeTap()
            input.typeText("The squat rack is taken. What should I do first?")
            snap("61_coach_typing")
            tapIfExists(app.buttons["sendMessage"])
            let reply = app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS 'Leg Press'")
            ).firstMatch
            _ = reply.waitForExistence(timeout: 20)
            sleep(2)
            snap("62_coach_reply")
        }
        let more = app.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'more' OR label CONTAINS[c] 'ellipsis'")
        ).firstMatch
        if more.exists {
            more.safeTap()
            sleep(1)
            snap("63_coach_menu")
            app.safeTap()
        }
    }

    // MARK: - Settings

    private func tourSettings() {
        launchToHome()
        // 1.9.0: Settings is a sheet from the gear in Today's toolbar.
        tapIfExists(app.buttons["settingsButton"])
        sleep(2)
        snap("70_settings")
        app.swipeUp()
        sleep(1)
        snap("71_settings_scrolled")
        app.swipeUp()
        sleep(1)
        snap("72_settings_bottom")

        // Evidence for the dead Form buttons: tap Restore and record what
        // happens (nothing, on the iOS 26.5 simulator). Never confirm it.
        let restore = app.buttons["Restore from Cloud"]
        scrollTo(restore)
        sleep(3)
        if restore.exists, restore.isHittable {
            restore.safeTap()
            sleep(3)
            snap("73_settings_after_restore_tap")
            tapIfExists(app.buttons["Cancel"])
        }
    }

    // MARK: - Helpers

    private func launchToHome() {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        sleep(4)
        tab("Today")
        sleep(1)
    }

    /// Taps a tab and confirms it took: a tap that lands while Home is still
    /// laying out its cards is sometimes dropped.
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
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(name)_\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The keyboard bar's Done sits in a Liquid Glass capsule; match it by
    /// label among hittable buttons, then confirm the keyboard went away.
    private func dismissKeyboard() {
        for _ in 0..<3 where app.isSoftwareKeyboardVisible {
            let done = app.buttons.matching(NSPredicate(format: "label == 'Done'"))
                .allElementsBoundByIndex
                .filter { $0.isHittable }
                .max(by: { $0.frame.minY < $1.frame.minY })
            if let done {
                done.safeTap()
            } else {
                app.swipeDown()
            }
            _ = app.waitForKeyboardToDisappear(timeout: 2)
        }
    }

    /// Home pins its cards above a short template list, so a template row
    /// can sit under the cards or the tab bar. Drag the visible strip of the
    /// list until the row is hittable.
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

    private func tapIfExists(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 2), element.isHittable {
            element.safeTap()
        }
    }

    private func dismissSheet() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while swipes < maxSwipes, !(element.exists && element.isHittable) {
            app.swipeUp()
            swipes += 1
        }
    }

    /// Typed queries: `descendants(matching: .any)` times out on a workout
    /// with four cards of set rows.
    private func setButtons(_ prefix: String) -> XCUIElementQuery {
        let base = prefix == "completeSet_" ? app.buttons : app.textFields
        return base.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func skipRest() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) { skip.safeTap() }
        sleep(1)
    }

    private func hittableExerciseMenu() -> XCUIElement? {
        app.buttons.matching(NSPredicate(format: "label == 'Exercise actions'"))
            .allElementsBoundByIndex
            .first(where: { $0.isHittable })
    }

    /// The first completion button under an exercise's header, by frame.
    private func firstCompleteButton(below exerciseName: String) -> XCUIElement? {
        let header = app.staticTexts[exerciseName]
        guard header.exists else { return nil }
        let headerY = header.frame.maxY
        return setButtons("completeSet_").allElementsBoundByIndex
            .filter { $0.frame.minY > headerY && $0.isHittable }
            .min(by: { $0.frame.minY < $1.frame.minY })
    }
}

private extension XCUIElement {
    /// Taps only when hittable, so one hidden element never ends the tour.
    func safeTap() {
        if exists, isHittable { tap() }
    }
}
