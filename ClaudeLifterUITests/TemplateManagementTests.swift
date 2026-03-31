import XCTest

final class TemplateManagementTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSeededTemplateAppearsOnHome() throws {
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 5))
    }

    func testNewTemplateButtonExists() throws {
        // Navigate to templates section via home or dedicated area
        XCTAssertTrue(app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 5))
        // Look for a templates section or new template button
        let newTemplateButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch
        XCTAssertTrue(newTemplateButton.waitForExistence(timeout: 5))
    }

    func testCreateNewTemplate() throws {
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS[c] 'Template'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testTemplateEditorNameFieldExists() throws {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.tap()
        XCTAssertTrue(app.textFields["templateName"].waitForExistence(timeout: 5))
    }

    func testTemplateEditorSaveButtonExists() throws {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["saveTemplate"].waitForExistence(timeout: 5))
    }

    func testTemplateEditorAddExerciseButtonExists() throws {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Template'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["addExerciseToTemplate"].waitForExistence(timeout: 5))
    }
}
