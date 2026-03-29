import Foundation
import SwiftData

protocol ChatMessageRepository: Sendable {
    func save(_ message: AIChatMessage) async throws
    func fetch(workoutId: UUID?) async throws -> [AIChatMessage]
    func deleteAll(workoutId: UUID?) async throws
}

final class SwiftDataChatMessageRepository: ChatMessageRepository, @unchecked Sendable {
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
}
