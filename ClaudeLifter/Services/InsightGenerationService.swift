import Foundation

// MARK: - Protocol

@MainActor
protocol InsightGenerationServiceProtocol {
    func shouldGenerateInsights() -> Bool
    func generateInsights() async throws -> [ProactiveInsight]
}

// MARK: - Implementation

@MainActor
final class InsightGenerationService: InsightGenerationServiceProtocol {

    static let lastGenerationKey = "lastInsightGenerationDate"
    private static let insightInterval: TimeInterval = 24 * 60 * 60

    private let anthropicService: any AnthropicServiceProtocol
    private let workoutRepository: any WorkoutRepository
    private let insightRepository: any InsightRepository
    private let defaults: UserDefaults
    private let settings: SettingsManager?

    init(
        anthropicService: any AnthropicServiceProtocol,
        workoutRepository: any WorkoutRepository,
        insightRepository: any InsightRepository,
        defaults: UserDefaults = .standard,
        settings: SettingsManager? = nil
    ) {
        self.anthropicService = anthropicService
        self.workoutRepository = workoutRepository
        self.insightRepository = insightRepository
        self.defaults = defaults
        self.settings = settings
    }

    func shouldGenerateInsights() -> Bool {
        // Respect the Settings toggle — if the user has disabled proactive
        // insights, don't burn API tokens generating ones they'll never see.
        if let settings, !settings.proactiveInsightsEnabled { return false }
        guard let lastDate = defaults.object(forKey: Self.lastGenerationKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastDate) > Self.insightInterval
    }

    func generateInsights() async throws -> [ProactiveInsight] {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let workouts = try await workoutRepository.fetchByDateRange(from: twoWeeksAgo, to: Date())

        let summary = buildWorkoutSummary(workouts)

        let systemPrompt = """
        You are a fitness coach analyzing workout data. Generate 1-3 brief, actionable insights.
        Each insight should be one of: suggestion, warning, or encouragement.
        Format each insight as: [TYPE] insight text
        Where TYPE is one of: suggestion, warning, encouragement
        """

        let messages = [ChatMessage(role: .user, text: "Here is my recent workout data:\n\(summary)\n\nProvide brief insights.")]

        // Use SettingsManager model if available, otherwise default to Haiku (#44 fix)
        let model = settings?.aiModel.rawValue ?? AIModel.haiku.rawValue

        var responseText = ""
        for try await event in anthropicService.streamChat(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: nil,
            model: model
        ) {
            if case .text(let text) = event {
                responseText += text
            }
        }

        let insights = parseInsights(responseText)

        for insight in insights {
            try await insightRepository.save(insight)
        }

        defaults.set(Date(), forKey: Self.lastGenerationKey)

        return insights
    }

    // MARK: - Private Helpers

    private func buildWorkoutSummary(_ workouts: [Workout]) -> String {
        guard !workouts.isEmpty else {
            return "No workouts recorded in the past 14 days."
        }

        var lines: [String] = ["Recent workouts (\(workouts.count) sessions):"]
        for workout in workouts.prefix(10) {
            let dateStr = workout.startedAt.formatted(date: .abbreviated, time: .omitted)
            let exerciseCount = workout.exercises.count
            lines.append("- \(dateStr): \(workout.name) (\(exerciseCount) exercises)")
        }
        return lines.joined(separator: "\n")
    }

    private func parseInsights(_ text: String) -> [ProactiveInsight] {
        let lines = text.components(separatedBy: .newlines)
        var insights: [ProactiveInsight] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let lower = trimmed.lowercased()
            let insightType: InsightType
            let content: String

            if lower.hasPrefix("[suggestion]") {
                insightType = .suggestion
                content = trimmed.dropFirst("[suggestion]".count).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("[warning]") {
                insightType = .warning
                content = trimmed.dropFirst("[warning]".count).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("[encouragement]") {
                insightType = .encouragement
                content = trimmed.dropFirst("[encouragement]".count).trimmingCharacters(in: .whitespaces)
            } else {
                insightType = .suggestion
                content = trimmed
            }

            guard !content.isEmpty else { continue }
            insights.append(ProactiveInsight(content: content, type: insightType))
        }

        return insights
    }
}
