import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("TrainingPreferenceRepository Tests")
struct TrainingPreferenceRepositoryTests {
    @Test("fetchAll returns empty when no preferences")
    @MainActor
    func fetchAllEmpty() async throws {
        let container = try makeTestContainer()
        let repo = SwiftDataTrainingPreferenceRepository(context: container.mainContext)
        let results = try await repo.fetchAll()
        #expect(results.isEmpty)
    }

    @Test("upsert inserts a new preference")
    @MainActor
    func upsertNew() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataTrainingPreferenceRepository(context: context)
        try await repo.upsert(key: "training_style", value: "hypertrophy", source: "user_stated")

        let results = try await repo.fetchAll()
        #expect(results.count == 1)
        #expect(results[0].key == "training_style")
        #expect(results[0].value == "hypertrophy")
        #expect(results[0].source == "user_stated")
    }

    @Test("upsert updates an existing preference")
    @MainActor
    func upsertExisting() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let pref = TrainingPreference(key: "injury", value: "bad left shoulder")
        context.insert(pref)
        try context.save()

        let repo = SwiftDataTrainingPreferenceRepository(context: context)
        try await repo.upsert(key: "injury", value: "bad right knee", source: "user_stated")

        let results = try await repo.fetchAll()
        #expect(results.count == 1)
        #expect(results[0].value == "bad right knee")
    }

    @Test("delete removes preference by key")
    @MainActor
    func deleteByKey() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(TrainingPreference(key: "training_style", value: "strength"))
        context.insert(TrainingPreference(key: "injury", value: "none"))
        try context.save()

        let repo = SwiftDataTrainingPreferenceRepository(context: context)
        try await repo.delete(key: "training_style")

        let results = try await repo.fetchAll()
        #expect(results.count == 1)
        #expect(results[0].key == "injury")
    }
}
