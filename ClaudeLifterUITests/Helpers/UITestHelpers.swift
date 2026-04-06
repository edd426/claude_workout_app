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
