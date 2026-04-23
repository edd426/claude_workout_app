import Testing
import Foundation
@testable import ClaudeLifter

@Suite("BuildInfo Tests")
struct BuildInfoTests {

    /// Regression test: the old implementation used Date() at first access,
    /// making buildTimestamp equal to the APP LAUNCH time, which misled users
    /// into believing a stale binary had just been rebuilt. The current
    /// implementation reads the main executable's modification time, which
    /// is set by the linker at build time. This test asserts the timestamp
    /// is at least a few seconds older than "now" — realistic because a
    /// build-and-launch cycle takes far longer than that.
    @Test("buildDate reflects link time, not runtime")
    func buildDateIsBeforeNow() throws {
        let now = Date()
        let buildDate = try #require(BuildInfo.buildDate,
                                     "buildDate should be derivable from the executable")
        #expect(buildDate < now,
                "buildDate \(buildDate) must be in the past, not in the future")
        let age = now.timeIntervalSince(buildDate)
        #expect(age >= 1,
                "buildDate should be at least 1s before test start; got \(age)s — is it being sampled at runtime instead of build time?")
    }

    @Test("summary contains version and a formatted timestamp")
    func summaryShape() {
        let summary = BuildInfo.summary
        #expect(summary.contains("ClaudeLifter"))
        #expect(summary.contains("Built:"))
        // 10-digit date fragment like "2026-04-23"
        let dateRegex = #/\d{4}-\d{2}-\d{2}/#
        #expect(summary.firstMatch(of: dateRegex) != nil,
                "summary should contain a yyyy-MM-dd timestamp: \(summary)")
    }
}
