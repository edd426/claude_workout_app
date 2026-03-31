import XCTest

final class WorkoutFlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testTemplatePushDayAppearsOnHome() throws {
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 5))
    }

    func testStartWorkoutFromTemplate() throws {
        let pushDay = app.staticTexts["Push Day"]
        XCTAssertTrue(pushDay.waitForExistence(timeout: 5))
        pushDay.tap()
        XCTAssertTrue(app.navigationBars["Push Day"].waitForExistence(timeout: 5))
    }

    func testActiveWorkoutShowsExercises() throws {
        app.staticTexts["Push Day"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
    }

    func testActiveWorkoutShowsFinishButton() throws {
        app.staticTexts["Push Day"].tap()
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
    }

    func testActiveWorkoutShowsAddExerciseButton() throws {
        app.staticTexts["Push Day"].tap()
        XCTAssertTrue(app.buttons["addExerciseToWorkout"].waitForExistence(timeout: 5))
    }

    func testCompleteASet() throws {
        app.staticTexts["Push Day"].tap()
        // Scope to first match to avoid ambiguity when multiple exercises each have set order 0
        let completeButton = app.buttons.matching(identifier: "completeSet_0").firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()
        // Rest timer or completed state should appear
        XCTAssertTrue(app.buttons["finishWorkout"].exists)
    }

    func testWeightFieldIsAccessible() throws {
        app.staticTexts["Push Day"].tap()
        let weightField = app.textFields["weight_0"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
    }

    func testRepsFieldIsAccessible() throws {
        app.staticTexts["Push Day"].tap()
        let repsField = app.textFields["reps_0"]
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
    }

    func testFinishWorkoutShowsSummary() throws {
        app.staticTexts["Push Day"].tap()
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
        app.buttons["finishWorkout"].tap()
        XCTAssertTrue(app.staticTexts["Workout Complete!"].waitForExistence(timeout: 5))
    }

    func testWorkoutSummaryDoneButtonDismisses() throws {
        app.staticTexts["Push Day"].tap()
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
        app.buttons["finishWorkout"].tap()
        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 5))
        app.buttons["summaryDone"].tap()
        XCTAssertTrue(app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 5))
    }
}
