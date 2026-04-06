import XCTest

final class EdgeCaseTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testFinishWorkoutWithNoSetsCompleted() throws {
        app.startWorkoutFromTemplate("Push Day")
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
        app.buttons["finishWorkout"].tap()
        // Should show summary (0 sets completed is valid)
        XCTAssertTrue(app.staticTexts["Workout Complete!"].waitForExistence(timeout: 5))
    }

    func testLongExerciseNameDoesNotBreakLayout() throws {
        app.tabBars.buttons["Exercises"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 5))
        app.navigationBars["Exercises"].buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["exerciseName"].waitForExistence(timeout: 5))
        app.textFields["exerciseName"].tap()
        let longName = "This Is A Very Long Exercise Name That Might Cause Layout Issues In The UI"
        app.textFields["exerciseName"].typeText(longName)
        XCTAssertTrue(app.buttons["saveExercise"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["exerciseName"].exists)
    }

    func testWhitespaceOnlyMessageNotSent() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.textFields["chatMessageInput"].waitForExistence(timeout: 5))
        app.textFields["chatMessageInput"].tap()
        app.textFields["chatMessageInput"].typeText("   ")
        XCTAssertFalse(app.buttons["sendMessage"].isEnabled)
    }

    func testRapidTabSwitchingDoesNotCrash() throws {
        for _ in 0..<5 {
            app.tabBars.buttons["History"].tap()
            app.tabBars.buttons["Exercises"].tap()
            app.tabBars.buttons["Coach"].tap()
            app.tabBars.buttons["Home"].tap()
        }
        XCTAssertTrue(app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 5))
    }

    func testPullToRefreshOnHistoryTab() throws {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        scrollView.swipeDown()
        // App should not crash and nav bar should still be visible
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    func testCancelTemplateCreationDoesNotSave() throws {
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.tap()
        XCTAssertTrue(app.textFields["templateName"].waitForExistence(timeout: 5))
        app.textFields["templateName"].tap()
        app.textFields["templateName"].typeText("Should Not Be Saved")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["Should Not Be Saved"].waitForExistence(timeout: 2))
    }
}
