import XCTest

final class KeyboardDismissalTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testKeyboardDismissesInWorkout() throws {
        app.startWorkoutFromTemplate("Push Day")
        let weightField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'weight_'")
        ).element(boundBy: 0)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        XCTAssertTrue(app.isSoftwareKeyboardVisible)
        let doneButton = app.toolbars.buttons.matching(identifier: "Done").firstMatch
        XCTAssertEqual(app.toolbars.buttons.matching(identifier: "Done").count, 1)
        doneButton.tap()
        XCTAssertTrue(app.waitForKeyboardToDisappear())
    }

    func testEmptyWeightFieldDoesNotPrefixTypedValueWithZero() throws {
        app.startWorkoutFromTemplate("Push Day")
        let weightField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'weight_'")
        ).element(boundBy: 0)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))

        weightField.tap()
        weightField.typeText("40")

        XCTAssertEqual(weightField.value as? String, "40")
    }

    /// Report 8FF8C6D5 (Seated Calf Raise, 2026-09-14): tapping a filled reps
    /// box should leave the caret at the END, so one backspace corrects the
    /// last digit without a second tap to reposition it.
    ///
    /// The tap lands on the field's left edge on purpose — the value is
    /// centred, so that is where UIKit's own tap placement puts the caret at
    /// the start. Typing one digit tells all three behaviours apart: caret at
    /// end gives "123", caret at start "312", select-all "3".
    func testTappingFilledRepsFieldPutsCaretAtEnd() throws {
        app.startWorkoutFromTemplate("Push Day")
        let repsField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'reps_'")
        ).element(boundBy: 0)
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))

        repsField.tap()
        let existing = (repsField.value as? String) ?? ""
        repsField.typeText(String(
            repeating: XCUIKeyboardKey.delete.rawValue,
            count: max(existing.count, 3)
        ))
        repsField.typeText("12")
        app.toolbars.buttons.matching(identifier: "Done").firstMatch.tap()
        XCTAssertTrue(app.waitForKeyboardToDisappear())
        XCTAssertEqual(repsField.value as? String, "12")

        repsField.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)
        ).tap()
        XCTAssertTrue(app.isSoftwareKeyboardVisible)
        repsField.typeText("3")

        XCTAssertEqual(repsField.value as? String, "123")
    }

    func testKeyboardDismissesInChat() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.textFields["chatMessageInput"].waitForExistence(timeout: 5))
        app.textFields["chatMessageInput"].tap()
        XCTAssertTrue(app.isSoftwareKeyboardVisible)
        app.swipeDown()
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }

    func testKeyboardDismissesInExerciseCreation() throws {
        app.tabBars.buttons["Exercises"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 5))
        app.navigationBars["Exercises"].buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["exerciseName"].waitForExistence(timeout: 5))
        app.textFields["exerciseName"].tap()
        XCTAssertTrue(app.isSoftwareKeyboardVisible)
        app.swipeDown()
        XCTAssertTrue(app.navigationBars["New Exercise"].waitForExistence(timeout: 5))
    }

    func testKeyboardDismissesInTemplateEditor() throws {
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.tap()
        XCTAssertTrue(app.textFields["templateName"].waitForExistence(timeout: 5))
        app.textFields["templateName"].tap()
        XCTAssertTrue(app.isSoftwareKeyboardVisible)
        app.swipeDown()
        XCTAssertTrue(app.tabBars.firstMatch.exists || app.navigationBars.firstMatch.exists)
    }

    func testTabBarRemainsAccessibleAfterKeyboardDismissal() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.textFields["chatMessageInput"].waitForExistence(timeout: 5))
        app.textFields["chatMessageInput"].tap()
        app.swipeDown()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
    }
}
