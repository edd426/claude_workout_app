import Foundation
@testable import ClaudeLifter

@MainActor
final class MockInsightRepository: InsightRepository {
    var insights: [ProactiveInsight] = []
    var savedInsights: [ProactiveInsight] = []
    var markedReadInsights: [ProactiveInsight] = []
    var errorToThrow: Error? = nil

    func fetchAll() async throws -> [ProactiveInsight] {
        if let error = errorToThrow { throw error }
        return insights
    }

    func fetchUnread() async throws -> [ProactiveInsight] {
        if let error = errorToThrow { throw error }
        return insights.filter { !$0.isRead }
    }

    func save(_ insight: ProactiveInsight) async throws {
        if let error = errorToThrow { throw error }
        savedInsights.append(insight)
        if !insights.contains(where: { $0.id == insight.id }) {
            insights.append(insight)
        }
    }

    func markAsRead(_ insight: ProactiveInsight) async throws {
        if let error = errorToThrow { throw error }
        markedReadInsights.append(insight)
        insight.isRead = true
    }

    func fetchPending() async throws -> [ProactiveInsight] {
        if let error = errorToThrow { throw error }
        return insights.filter { $0.syncStatus == .pending }
    }
}
