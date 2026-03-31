import Foundation
@testable import ClaudeLifter

@MainActor
final class MockInsightGenerationService: InsightGenerationServiceProtocol {
    var stubbedShouldGenerate = false
    var stubbedInsights: [ProactiveInsight] = []
    var stubbedError: Error?

    var shouldGenerateCallCount = 0
    var generateCallCount = 0

    func shouldGenerateInsights() -> Bool {
        shouldGenerateCallCount += 1
        return stubbedShouldGenerate
    }

    func generateInsights() async throws -> [ProactiveInsight] {
        generateCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedInsights
    }
}
