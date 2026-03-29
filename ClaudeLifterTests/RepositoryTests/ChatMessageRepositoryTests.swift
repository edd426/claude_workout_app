import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("ChatMessageRepository Tests")
struct ChatMessageRepositoryTests {
    @Test("save persists a message")
    @MainActor
    func saveMessage() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataChatMessageRepository(context: context)
        let msg = AIChatMessage(role: .user, content: "How many sets?")
        try await repo.save(msg)

        let fetched = try context.fetch(FetchDescriptor<AIChatMessage>())
        #expect(fetched.count == 1)
    }

    @Test("fetch with nil workoutId returns general messages")
    @MainActor
    func fetchGeneralMessages() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataChatMessageRepository(context: context)

        let general = AIChatMessage(role: .user, content: "General question", workoutId: nil)
        let workoutMsg = AIChatMessage(role: .user, content: "Workout question", workoutId: UUID())
        context.insert(general)
        context.insert(workoutMsg)
        try context.save()

        let results = try await repo.fetch(workoutId: nil)
        #expect(results.count == 1)
        #expect(results[0].content == "General question")
    }

    @Test("fetch with workoutId returns matching messages")
    @MainActor
    func fetchByWorkoutId() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataChatMessageRepository(context: context)

        let workoutId = UUID()
        let msg1 = AIChatMessage(role: .user, content: "First", workoutId: workoutId)
        let msg2 = AIChatMessage(role: .assistant, content: "Second", workoutId: workoutId)
        let other = AIChatMessage(role: .user, content: "Other", workoutId: UUID())
        context.insert(msg1)
        context.insert(msg2)
        context.insert(other)
        try context.save()

        let results = try await repo.fetch(workoutId: workoutId)
        #expect(results.count == 2)
    }

    @Test("fetch returns messages sorted by timestamp ascending")
    @MainActor
    func fetchSorted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataChatMessageRepository(context: context)

        let early = AIChatMessage(role: .user, content: "First", timestamp: Date(timeIntervalSinceNow: -100))
        let late = AIChatMessage(role: .assistant, content: "Second", timestamp: Date(timeIntervalSinceNow: -10))
        context.insert(early)
        context.insert(late)
        try context.save()

        let results = try await repo.fetch(workoutId: nil)
        #expect(results[0].content == "First")
        #expect(results[1].content == "Second")
    }

    @Test("deleteAll removes all messages for a workoutId")
    @MainActor
    func deleteAll() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataChatMessageRepository(context: context)

        let workoutId = UUID()
        context.insert(AIChatMessage(role: .user, content: "A", workoutId: workoutId))
        context.insert(AIChatMessage(role: .assistant, content: "B", workoutId: workoutId))
        context.insert(AIChatMessage(role: .user, content: "C", workoutId: nil))
        try context.save()

        try await repo.deleteAll(workoutId: workoutId)

        let remaining = try await repo.fetch(workoutId: nil)
        #expect(remaining.count == 1)
        #expect(remaining[0].content == "C")
    }
}
