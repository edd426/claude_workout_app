import XCTest

extension XCUIApplication {
    func launchForTesting() {
        launchArguments += ["-UITesting", "-seedTestData"]
        launch()
    }

    /// Taps a template by name, then taps "Start Workout" on the preview screen
    /// to navigate into the active workout view.
    func startWorkoutFromTemplate(_ name: String, file: StaticString = #file, line: UInt = #line) {
        let templateText = staticTexts[name]
        XCTAssertTrue(templateText.waitForExistence(timeout: 5), "Template '\(name)' not found", file: file, line: line)
        templateText.tap()
        let startButton = buttons["startWorkoutFromPreview"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Workout button not found on preview", file: file, line: line)
        startButton.tap()
    }
}

extension XCUIApplication {
    /// Whether the software keyboard is on screen.
    ///
    /// `keyboards.count > 0` is **not** reliable. On Evan's iPhone the keyboard
    /// is exposed as an `Other` element with identifier `"keyboard"` rather than
    /// as a `Keyboard`-type element, so `keyboards` is empty while `keys`
    /// returns all twelve of a decimal pad's keys and the text field reports
    /// keyboard focus. The device has a third-party keyboard installed (a
    /// "Next keyboard" button is present), which is what differs from the
    /// simulator. Four `KeyboardDismissalTests` failed permanently on device
    /// for this reason alone — the app was behaving correctly throughout.
    ///
    /// Checking for keys works on both device and simulator.
    var isSoftwareKeyboardVisible: Bool {
        keyboards.count > 0 || keys.count > 0
    }

    /// Waits for the keyboard to disappear, since dismissal is animated.
    func waitForKeyboardToDisappear(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while isSoftwareKeyboardVisible, Date() < deadline {
            _ = keys.firstMatch.waitForExistence(timeout: 0.2)
        }
        return !isSoftwareKeyboardVisible
    }
}

extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let currentValue = value as? String, !currentValue.isEmpty else {
            typeText(text)
            return
        }
        tap()
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        typeText(deleteString)
        typeText(text)
    }
}
