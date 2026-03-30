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
        let all = try context.fetch(FetchDescriptor<AIChatMessage>(
            sortBy: [SortDescriptor(\.timestamp)]
        ))
        if let workoutId {
            return all.filter { $0.workoutId == workoutId }
        } else {
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
        let all = try context.fetch(FetchDescriptor<AIChatMessage>())
        return all.filter { $0.syncStatus == .pending }
    }
}
