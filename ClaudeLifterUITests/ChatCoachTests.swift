import XCTest

final class ChatCoachTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testCoachTabNavigates() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
    }

    func testChatInputFieldExists() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.textFields["chatMessageInput"].waitForExistence(timeout: 5))
    }

    func testSendButtonExistsInChat() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.buttons["sendMessage"].waitForExistence(timeout: 5))
    }

    func testSendButtonDisabledWhenInputEmpty() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.buttons["sendMessage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sendMessage"].isEnabled)
    }

    func testSendButtonEnabledAfterTyping() throws {
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.textFields["chatMessageInput"].waitForExistence(timeout: 5))
        app.textFields["chatMessageInput"].tap()
        app.textFields["chatMessageInput"].typeText("How should I warm up?")
        XCTAssertTrue(app.buttons["sendMessage"].isEnabled)
    }
}
