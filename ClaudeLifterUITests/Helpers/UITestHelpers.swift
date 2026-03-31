import XCTest

extension XCUIApplication {
    func launchForTesting() {
        launchArguments += ["-UITesting", "-seedTestData"]
        launch()
    }
}

extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let currentValue = value as? String, !currentValue.isEmpty else {
            typeText(text)
            return
        }
        tap()
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
        typeText(deleteString)
        typeText(text)
    }
}
