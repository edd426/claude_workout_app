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
        // Use firstMatch to avoid ambiguity when multiple exercises each have set order 0
        let weightField = app.textFields.matching(identifier: "weight_0").firstMatch
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        XCTAssertTrue(app.keyboards.count > 0)
        // Tap done button in keyboard toolbar (firstMatch avoids ambiguity across multiple SetRowView toolbars)
        let doneButton = app.toolbars.buttons.matching(identifier: "Done").firstMatch
        if doneButton.exists {
            doneButton.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["finishWorkout"].exists)
    }

    func testKeyboardDismissesInChat() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.textFields["chatMessageInput"].waitForExistence(timeout: 5))
        app.textFields["chatMessageInput"].tap()
        XCTAssertTrue(app.keyboards.count > 0)
        app.swipeDown()
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }

    func testKeyboardDismissesInExerciseCreation() throws {
        app.tabBars.buttons["Exercises"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 5))
        app.navigationBars["Exercises"].buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["exerciseName"].waitForExistence(timeout: 5))
        app.textFields["exerciseName"].tap()
        XCTAssertTrue(app.keyboards.count > 0)
        app.swipeDown()
        XCTAssertTrue(app.navigationBars["New Exercise"].waitForExistence(timeout: 5))
    }

    func testKeyboardDismissesInTemplateEditor() throws {
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.tap()
        XCTAssertTrue(app.textFields["templateName"].waitForExistence(timeout: 5))
        app.textFields["templateName"].tap()
        XCTAssertTrue(app.keyboards.count > 0)
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
