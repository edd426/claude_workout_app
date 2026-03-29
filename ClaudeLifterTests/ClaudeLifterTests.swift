import Testing
@testable import ClaudeLifter

@Suite("ClaudeLifter Smoke Tests")
struct ClaudeLifterSmokeTests {
    @Test("App module can be imported")
    func moduleImports() {
        #expect(true)
    }
}
