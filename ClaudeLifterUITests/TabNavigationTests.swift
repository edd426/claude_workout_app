import XCTest

final class TabNavigationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testTabBarIsVisible() throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testHomeTabIsSelectedByDefault() throws {
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
    }

    func testNavigateToHistoryTab() throws {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    func testNavigateToExercisesTab() throws {
        app.tabBars.buttons["Exercises"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 5))
    }

    func testNavigateToCoachTab() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
    }

    func testNavigateBackToHomeTab() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
    }

    func testAllFiveTabsExist() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        // 1.9.0: Today · History · Body · Exercises · Coach. Settings is a
        // sheet from Today's gear, not a tab.
        XCTAssertTrue(tabBar.buttons["Today"].exists)
        XCTAssertTrue(tabBar.buttons["History"].exists)
        XCTAssertTrue(tabBar.buttons["Body"].exists)
        XCTAssertTrue(tabBar.buttons["Exercises"].exists)
        XCTAssertTrue(tabBar.buttons["Coach"].exists)
        XCTAssertFalse(tabBar.buttons["Settings"].exists)
    }
}
