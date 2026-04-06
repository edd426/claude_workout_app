import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("fetchPending + fetchByDateRange Repository Tests")
struct FetchPendingTests {
    // MARK: - WorkoutRepository

    @Test("WorkoutRepository fetchPending returns only pending workouts")
    @MainActor
    func workoutFetchPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataWorkoutRepository(context: context)

        let pending = Workout(name: "Pending", startedAt: .now, syncStatus: .pending)
        let synced = Workout(name: "Synced", startedAt: .now, syncStatus: .synced)
        context.insert(pending)
        context.insert(synced)
        try context.save()

        let results = try await repo.fetchPending()
        #expect(results.count == 1)
        #expect(results[0].name == "Pending")
    }

    @Test("WorkoutRepository fetchByDateRange returns workouts in range")
    @MainActor
    func workoutFetchByDateRange() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataWorkoutRepository(context: context)

        let base = Date(timeIntervalSinceReferenceDate: 0)
        let inside = Workout(name: "Inside", startedAt: base.addingTimeInterval(3600))
        let before = Workout(name: "Before", startedAt: base.addingTimeInterval(-3600))
        let after = Workout(name: "After", startedAt: base.addingTimeInterval(7200))
        context.insert(inside)
        context.insert(before)
        context.insert(after)
        try context.save()

        let from = base
        let to = base.addingTimeInterval(5000)
        let results = try await repo.fetchByDateRange(from: from, to: to)
        #expect(results.count == 1)
        #expect(results[0].name == "Inside")
    }

    @Test("WorkoutRepository fetchByDateRange is inclusive of boundaries")
    @MainActor
    func workoutFetchByDateRangeBoundaries() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataWorkoutRepository(context: context)

        let from = Date(timeIntervalSinceReferenceDate: 1000)
        let to = Date(timeIntervalSinceReferenceDate: 2000)
        let atStart = Workout(name: "At Start", startedAt: from)
        let atEnd = Workout(name: "At End", startedAt: to)
        context.insert(atStart)
        context.insert(atEnd)
        try context.save()

        let results = try await repo.fetchByDateRange(from: from, to: to)
        #expect(results.count == 2)
    }

    // MARK: - TemplateRepository

    @Test("TemplateRepository fetchPending returns only pending templates")
    @MainActor
    func templateFetchPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataTemplateRepository(context: context)

        let pending = WorkoutTemplate(name: "Pending")
        pending.syncStatus = .pending
        let synced = WorkoutTemplate(name: "Synced")
        synced.syncStatus = .synced
        context.insert(pending)
        context.insert(synced)
        try context.save()

        let results = try await repo.fetchPending()
        #expect(results.count == 1)
        #expect(results[0].name == "Pending")
    }

    // MARK: - ChatMessageRepository

    @Test("ChatMessageRepository fetchPending returns only pending messages")
    @MainActor
    func chatFetchPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataChatMessageRepository(context: context)

        let pending = AIChatMessage(role: .user, content: "Pending", syncStatus: .pending)
        let synced = AIChatMessage(role: .assistant, content: "Synced", syncStatus: .synced)
        context.insert(pending)
        context.insert(synced)
        try context.save()

        let results = try await repo.fetchPending()
        #expect(results.count == 1)
        #expect(results[0].content == "Pending")
    }

    // MARK: - InsightRepository

    @Test("InsightRepository fetchPending returns only pending insights")
    @MainActor
    func insightFetchPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataInsightRepository(context: context)

        let pending = ProactiveInsight(content: "Pending insight", type: .suggestion, syncStatus: .pending)
        let synced = ProactiveInsight(content: "Synced insight", type: .warning, syncStatus: .synced)
        context.insert(pending)
        context.insert(synced)
        try context.save()

        let results = try await repo.fetchPending()
        #expect(results.count == 1)
        #expect(results[0].content == "Pending insight")
    }

    // MARK: - TrainingPreferenceRepository

    @Test("TrainingPreferenceRepository fetchPending returns only pending preferences")
    @MainActor
    func prefFetchPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataTrainingPreferenceRepository(context: context)

        let pending = TrainingPreference(key: "style", value: "strength", syncStatus: .pending)
        let synced = TrainingPreference(key: "injury", value: "none", syncStatus: .synced)
        context.insert(pending)
        context.insert(synced)
        try context.save()

        let results = try await repo.fetchPending()
        #expect(results.count == 1)
        #expect(results[0].key == "style")
    }
}
