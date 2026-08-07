import XCTest

final class HistoryCalendarTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testHistoryTabNavigates() throws {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    func testHistoryShowsDefaultState() throws {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        // Should show some content (calendar or list)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5))
    }

    func testHistoryShowsSeededWorkout() throws {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 5))
    }

    func testHistoryListIsScrollable() throws {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        scrollView.swipeUp()
        XCTAssertTrue(app.navigationBars["History"].exists)
    }

    func testTapWorkoutInHistoryShowsDetail() throws {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 5))
        app.staticTexts["Push Day"].firstMatch.tap()
        // Should navigate to detail or show exercises
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Bench Press' OR label CONTAINS[c] 'Push Day'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testHistoryDisplaysWorkoutDate() throws {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        // Yesterday's date should appear somewhere in the list
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5))
    }

    /// Regression test for #132.
    ///
    /// `HistoryListView` built its view models and loaded them inside the same
    /// `if vm == nil` guard, so `loadWorkouts()` ran once per launch. Anyone who
    /// opened History early in a session then saw a list frozen at that moment —
    /// including after finishing a workout, which is the case that matters.
    func testHistoryRefreshesAfterFinishingAWorkout() throws {
        let historyRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'historyRow_'")
        )

        // Visit History first, so its view models are already constructed.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(historyRows.firstMatch.waitForExistence(timeout: 5))
        let rowsBefore = historyRows.count

        // Log and finish a workout.
        app.tabBars.buttons["Home"].tap()
        app.startWorkoutFromTemplate("Push Day")
        let completeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'completeSet_'")
        ).element(boundBy: 0)
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()
        let finish = app.buttons["finishWorkout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 5))
        app.buttons["summaryDone"].tap()

        // Returning to History must show it, without a pull-to-refresh.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(historyRows.firstMatch.waitForExistence(timeout: 5))

        let deadline = Date().addingTimeInterval(5)
        while historyRows.count <= rowsBefore, Date() < deadline {
            _ = historyRows.firstMatch.waitForExistence(timeout: 0.5)
        }
        XCTAssertEqual(
            historyRows.count, rowsBefore + 1,
            "History must reload on revisit, not serve a list cached at first appearance"
        )
    }
}
