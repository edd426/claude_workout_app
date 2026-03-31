import Testing
import Foundation
@testable import ClaudeLifter

@Suite("InsightGenerationService Tests")
@MainActor
struct InsightGenerationServiceTests {

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suiteName = "test-insights-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return defaults
    }

    private func makeService(
        anthropicService: MockAnthropicService = MockAnthropicService(),
        workoutRepository: MockWorkoutRepository = MockWorkoutRepository(),
        insightRepository: MockInsightRepository = MockInsightRepository(),
        defaults: UserDefaults
    ) -> InsightGenerationService {
        InsightGenerationService(
            anthropicService: anthropicService,
            workoutRepository: workoutRepository,
            insightRepository: insightRepository,
            defaults: defaults
        )
    }

    // MARK: - shouldGenerateInsights

    @Test("shouldGenerateInsights returns true when more than 24h since last")
    func shouldGenerateInsightsReturnsTrueWhenMoreThan24Hours() {
        let defaults = makeDefaults()
        defer { defaults.removeSuite(named: defaults.description) }

        let pastDate = Date().addingTimeInterval(-(25 * 60 * 60))
        defaults.set(pastDate, forKey: InsightGenerationService.lastGenerationKey)

        let svc = makeService(defaults: defaults)
        #expect(svc.shouldGenerateInsights() == true)
    }

    @Test("shouldGenerateInsights returns false when less than 24h since last")
    func shouldGenerateInsightsReturnsFalseWhenLessThan24Hours() {
        let defaults = makeDefaults()
        defer { defaults.removeSuite(named: defaults.description) }

        let recentDate = Date().addingTimeInterval(-(1 * 60 * 60))
        defaults.set(recentDate, forKey: InsightGenerationService.lastGenerationKey)

        let svc = makeService(defaults: defaults)
        #expect(svc.shouldGenerateInsights() == false)
    }

    @Test("shouldGenerateInsights returns true on first launch")
    func shouldGenerateInsightsReturnsTrueOnFirstLaunch() {
        let defaults = makeDefaults()
        defer { defaults.removeSuite(named: defaults.description) }

        let svc = makeService(defaults: defaults)
        #expect(svc.shouldGenerateInsights() == true)
    }

    // MARK: - generateInsights

    @Test("generateInsights creates ProactiveInsight objects")
    func generateInsightsCreatesProactiveInsightObjects() async throws {
        let defaults = makeDefaults()
        defer { defaults.removeSuite(named: defaults.description) }

        let mockAnthropic = MockAnthropicService()
        mockAnthropic.stubbedEvents = [
            .text("[suggestion] Rest more between sessions"),
            .complete
        ]

        let insightRepo = MockInsightRepository()
        let svc = makeService(
            anthropicService: mockAnthropic,
            insightRepository: insightRepo,
            defaults: defaults
        )

        let insights = try await svc.generateInsights()

        #expect(insights.count == 1)
        #expect(insights[0].type == .suggestion)
        #expect(insights[0].content.contains("Rest more between sessions"))
        #expect(insightRepo.savedInsights.count == 1)
    }

    @Test("generateInsights updates lastInsightGenerationDate")
    func generateInsightsUpdatesLastGenerationDate() async throws {
        let defaults = makeDefaults()
        defer { defaults.removeSuite(named: defaults.description) }

        let mockAnthropic = MockAnthropicService()
        mockAnthropic.stubbedEvents = [.text("[suggestion] Keep it up"), .complete]

        let svc = makeService(anthropicService: mockAnthropic, defaults: defaults)

        #expect(defaults.object(forKey: InsightGenerationService.lastGenerationKey) == nil)
        _ = try await svc.generateInsights()
        let saved = defaults.object(forKey: InsightGenerationService.lastGenerationKey) as? Date
        #expect(saved != nil)
    }

    @Test("generateInsights handles empty workout history")
    func generateInsightsHandlesEmptyWorkoutHistory() async throws {
        let defaults = makeDefaults()
        defer { defaults.removeSuite(named: defaults.description) }

        let mockAnthropic = MockAnthropicService()
        mockAnthropic.stubbedEvents = [
            .text("[encouragement] Start your first workout today!"),
            .complete
        ]

        let emptyWorkoutRepo = MockWorkoutRepository()
        let svc = makeService(
            anthropicService: mockAnthropic,
            workoutRepository: emptyWorkoutRepo,
            defaults: defaults
        )

        let insights = try await svc.generateInsights()

        #expect(mockAnthropic.streamChatCallCount == 1)
        #expect(insights.count == 1)
        #expect(insights[0].type == .encouragement)
    }

    @Test("generated insights have correct InsightType values")
    func generatedInsightsHaveCorrectInsightTypeValues() async throws {
        let defaults = makeDefaults()
        defer { defaults.removeSuite(named: defaults.description) }

        let mockAnthropic = MockAnthropicService()
        mockAnthropic.stubbedEvents = [
            .text("[suggestion] Try progressive overload\n[warning] You haven't trained legs in 2 weeks\n[encouragement] Great bench progress!"),
            .complete
        ]

        let insightRepo = MockInsightRepository()
        let svc = makeService(
            anthropicService: mockAnthropic,
            insightRepository: insightRepo,
            defaults: defaults
        )

        let insights = try await svc.generateInsights()

        #expect(insights.count == 3)
        let types = insights.map(\.type)
        #expect(types.contains(.suggestion))
        #expect(types.contains(.warning))
        #expect(types.contains(.encouragement))
    }
}
