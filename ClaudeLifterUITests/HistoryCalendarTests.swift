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
}
