import XCTest

final class FullUserSessionTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testCompleteUserSession() throws {
        // 1. Home tab is visible with seeded template
        XCTAssertTrue(app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 5))

        // 2. Start a workout from Push Day template
        app.startWorkoutFromTemplate("Push Day")
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))

        // 3. Complete the first UUID-identified set.
        let completeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'completeSet_'")
        ).element(boundBy: 0)
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        // 4. Finish workout
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
        app.buttons["finishWorkout"].tap()

        // 5. Verify summary screen
        XCTAssertTrue(app.staticTexts["Workout Complete!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 5))
        app.buttons["summaryDone"].tap()

        // 6. Verify we are back on the home tab after workout completion
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 8))
    }
}
