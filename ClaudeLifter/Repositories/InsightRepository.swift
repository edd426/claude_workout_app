import Foundation
import SwiftData

@MainActor
protocol InsightRepository {
    func fetchAll() async throws -> [ProactiveInsight]
    func fetchUnread() async throws -> [ProactiveInsight]
    func save(_ insight: ProactiveInsight) async throws
    func markAsRead(_ insight: ProactiveInsight) async throws
    func fetchPending() async throws -> [ProactiveInsight]
}

@MainActor
final class SwiftDataInsightRepository: InsightRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [ProactiveInsight] {
        let descriptor = FetchDescriptor<ProactiveInsight>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchUnread() async throws -> [ProactiveInsight] {
        let descriptor = FetchDescriptor<ProactiveInsight>(
            predicate: #Predicate { $0.isRead == false },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func save(_ insight: ProactiveInsight) async throws {
        context.insert(insight)
        try context.save()
    }

    func markAsRead(_ insight: ProactiveInsight) async throws {
        insight.isRead = true
        try context.save()
    }

    func fetchPending() async throws -> [ProactiveInsight] {
        // SwiftData #Predicate cannot traverse enum .rawValue at runtime,
        // so we use in-memory filtering. Insights are a small, bounded set.
        let all = try context.fetch(FetchDescriptor<ProactiveInsight>())
        return all.filter { $0.syncStatus == .pending }
    }
}
