import Foundation
import SwiftData

@MainActor
protocol ChatMessageRepository {
    func save(_ message: AIChatMessage) async throws
    func fetch(workoutId: UUID?) async throws -> [AIChatMessage]
    func deleteAll(workoutId: UUID?) async throws
    func fetchPending() async throws -> [AIChatMessage]
}

@MainActor
final class SwiftDataChatMessageRepository: ChatMessageRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save(_ message: AIChatMessage) async throws {
        context.insert(message)
        try context.save()
    }

    func fetch(workoutId: UUID?) async throws -> [AIChatMessage] {
        if let targetId = workoutId {
            let descriptor = FetchDescriptor<AIChatMessage>(
                predicate: #Predicate { $0.workoutId == targetId },
                sortBy: [SortDescriptor(\.timestamp)]
            )
            return try context.fetch(descriptor)
        } else {
            // workoutId == nil: filter in memory since SwiftData predicates
            // have limitations with optional nil comparisons.
            let all = try context.fetch(FetchDescriptor<AIChatMessage>(
                sortBy: [SortDescriptor(\.timestamp)]
            ))
            return all.filter { $0.workoutId == nil }
        }
    }

    func deleteAll(workoutId: UUID?) async throws {
        let messages = try await fetch(workoutId: workoutId)
        for message in messages {
            context.delete(message)
        }
        try context.save()
    }

    func fetchPending() async throws -> [AIChatMessage] {
        // SwiftData #Predicate cannot traverse enum .rawValue at runtime,
        // so we use in-memory filtering. Pending messages are always recent.
        let all = try context.fetch(FetchDescriptor<AIChatMessage>())
        return all.filter { $0.syncStatus == .pending }
    }
}
