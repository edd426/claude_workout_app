import Foundation
@testable import ClaudeLifter

@MainActor
final class MockChatMessageRepository: ChatMessageRepository {
    var messages: [AIChatMessage] = []
    var saveCallCount = 0
    var errorToThrow: Error? = nil

    func save(_ message: AIChatMessage) async throws {
        saveCallCount += 1
        if let error = errorToThrow { throw error }
        messages.append(message)
    }

    func fetch(workoutId: UUID?) async throws -> [AIChatMessage] {
        if let error = errorToThrow { throw error }
        if let workoutId {
            return messages.filter { $0.workoutId == workoutId }
        } else {
            return messages.filter { $0.workoutId == nil }
        }
    }

    func deleteAll(workoutId: UUID?) async throws {
        if let error = errorToThrow { throw error }
        if let workoutId {
            messages.removeAll { $0.workoutId == workoutId }
        } else {
            messages.removeAll { $0.workoutId == nil }
        }
    }

    func fetchPending() async throws -> [AIChatMessage] {
        if let error = errorToThrow { throw error }
        return messages.filter { $0.syncStatus == .pending }
    }
}
