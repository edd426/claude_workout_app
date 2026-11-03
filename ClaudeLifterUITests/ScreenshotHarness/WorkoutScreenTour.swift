import XCTest

/// Screenshot tour of the 1.9.0 any-order workout screen: the strip,
/// collapsed and expanded cards, "Machine taken", the card menu, skip, the
/// keyboard bar, the rest bar and the photo viewer.
///
/// Same environment as `ScreenshotTour` (seeded store, mock server, never
/// production); skipped unless `SCREENSHOT_DIR` is set. `TOUR_TEMPLATE`
/// picks the template (default "Lower A"). With `TOUR_LIVE_RESIZE=1` it starts
/// the workout, writes `READY_FOR_RESIZE` into `SCREENSHOT_DIR` and waits, so
/// the host can switch the text size to AX5 live (Home hides its template
/// rows at AX5), then takes the AX5 shots.
final class WorkoutScreenTour: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!
    private var suffix = "light"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Workout tour runs only with SCREENSHOT_DIR set")
        }
        outputDirectory = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        suffix = env["SCREENSHOT_SUFFIX"] ?? "light"
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

    func testWorkoutScreen() throws {
        let env = ProcessInfo.processInfo.environment
        startWorkout(env["TOUR_TEMPLATE"] ?? "Lower A")
        if env["TOUR_LIVE_RESIZE"] == "1" {
            accessibilitySizes()
        } else {
            tour()
        }
    }

    private func tour() {
        snap("w01_start")

        // Machine taken: menu, swap, undo.
        if tapFirst(app.buttons.matching(identifier: "machineTaken")) {
            sleep(1)
            snap("w02_machine_taken_menu")
            // Menu items do not always carry their identifier; the seeded
            // fixtures list Leg Press and Goblet Squat on Lower A's squat.
            let alternative = NSPredicate(
                format: "identifier BEGINSWITH 'alternative_' OR label BEGINSWITH 'Leg Press' OR label BEGINSWITH 'Goblet Squat'"
            )
            if tapFirst(app.buttons.matching(alternative)) {
                sleep(2)
                snap("w03_swapped")
                if tapFirst(app.buttons.matching(identifier: "machineTaken")) {
                    sleep(1)
                    snap("w04_undo_in_menu")
                    let undo = NSPredicate(format: "identifier == 'undoSwap' OR label BEGINSWITH 'Undo'")
                    if !tapFirst(app.buttons.matching(undo)) { dismissMenu() }
                    sleep(1)
                }
            } else {
                dismissMenu()
            }
        }

        // One tap logs a planned set; the rest bar appears.
        if tapFirst(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'completeSet_'"))) {
            sleep(1)
            snap("w05_set_logged_rest")
            _ = tapFirst(app.buttons.matching(NSPredicate(format: "label == 'Skip rest'")))
            sleep(1)
        }

        // Keyboard bar: −2.5 / +2.5 / ✓ Log set.
        let weights = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'weight_'"))
        if weights.count > 1 {
            weights.element(boundBy: 1).tap()
            sleep(1)
            snap("w06_keyboard_bar")
            if tapFirst(app.buttons.matching(identifier: "weightPlus")) {
                sleep(1)
                snap("w07_after_plus")
            }
            if tapFirst(app.buttons.matching(identifier: "logFocusedSet")) {
                sleep(1)
                snap("w08_logged_from_bar")
            }
            _ = tapFirst(app.buttons.matching(NSPredicate(format: "label == 'Skip rest'")))
            sleep(1)
        }

        // Out of order: the last exercise from the strip.
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stripChip_'"))
        if chips.count > 2 {
            let strip = app.scrollViews["exerciseStrip"]
            if strip.exists { strip.swipeLeft() }
            sleep(1)
            let last = chips.element(boundBy: chips.count - 1)
            if isOnScreen(last) { last.tap() }
            sleep(2)
            snap("w09_out_of_order")
        }

        // The card menu, then Skip today on the open card.
        let menus = app.buttons.matching(identifier: "exerciseActions")
        if let menu = menus.allElementsBoundByIndex.last(where: { isOnScreen($0) }) {
            menu.tap()
            sleep(1)
            snap("w10_card_menu")
            let skip = NSPredicate(format: "identifier == 'skipExercise' OR label == 'Skip today'")
            if tapFirst(app.buttons.matching(skip)) {
                sleep(1)
                snap("w11_skipped")
            } else {
                dismissMenu()
            }
        }

        // The machine photo, full screen.
        if tapFirst(app.buttons.matching(identifier: "exercisePhoto")) {
            sleep(3)
            snap("w12_photo_viewer")
            _ = tapFirst(app.buttons.matching(identifier: "closeExercisePhoto"))
            sleep(1)
        }

        // An exercise added mid-workout: committed values, not ghosts (#174).
        app.swipeUp()
        sleep(1)
        if tapFirst(app.buttons.matching(identifier: "addExerciseToWorkout")) {
            sleep(2)
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 3) {
                search.tap()
                sleep(1)
                search.typeText("leg press")
                sleep(2)
                let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Leg Press'")).firstMatch
                if row.waitForExistence(timeout: 3), isOnScreen(row) {
                    row.tap()
                    sleep(3)
                    snap("w13_added_exercise")
                } else {
                    _ = tapFirst(app.buttons.matching(NSPredicate(format: "label == 'Cancel'")))
                }
            }
        }
    }

    private func accessibilitySizes() {
        let marker = outputDirectory.appendingPathComponent("READY_FOR_RESIZE")
        try? Data().write(to: marker)
        sleep(40)
        snap("w01_start")
        app.swipeUp()
        sleep(2)
        snap("w02_rows")
        app.swipeUp()
        sleep(2)
        snap("w03_rows_lower")
        try? FileManager.default.removeItem(at: marker)
    }

    private func startWorkout(_ templateName: String) {
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
        sleep(4)
    }

    @discardableResult
    private func tapFirst(_ query: XCUIElementQuery) -> Bool {
        guard let element = query.allElementsBoundByIndex.first(where: { isOnScreen($0) }) else {
            return false
        }
        element.tap()
        return true
    }

    /// `isHittable` throws for elements scrolled out of a scroll view, so
    /// check the frame against the screen instead.
    private func isOnScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Taps the navigation title, which has no action, to close a menu.
    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.075)).tap()
        sleep(1)
    }

    private func snap(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: outputDirectory.appendingPathComponent("\(name)_\(suffix).png"))
    }

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
