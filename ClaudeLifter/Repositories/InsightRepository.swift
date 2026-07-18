import Foundation
import SwiftData

@MainActor
protocol InsightRepository {
    func fetchAll() async throws -> [ProactiveInsight]
    func fetch(id: UUID) async throws -> ProactiveInsight?
    func fetchUnread() async throws -> [ProactiveInsight]
    func save(_ insight: ProactiveInsight) async throws
    func markAsRead(_ insight: ProactiveInsight) async throws
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

    func fetch(id: UUID) async throws -> ProactiveInsight? {
        let descriptor = FetchDescriptor<ProactiveInsight>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
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
        insight.recordChange()
        try context.save()
    }
}
