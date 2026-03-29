import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("ExerciseRepository Tests")
struct ExerciseRepositoryTests {
    @Test("fetchAll returns empty when no exercises")
    @MainActor
    func fetchAllEmpty() async throws {
        let container = try makeTestContainer()
        let repo = SwiftDataExerciseRepository(context: container.mainContext)
        let results = try await repo.fetchAll()
        #expect(results.isEmpty)
    }

    @Test("fetchAll returns inserted exercises")
    @MainActor
    func fetchAll() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(TestFixtures.makeExercise(name: "Bench Press"))
        context.insert(TestFixtures.makeExercise(name: "Squat"))
        try context.save()

        let repo = SwiftDataExerciseRepository(context: context)
        let results = try await repo.fetchAll()
        #expect(results.count == 2)
    }

    @Test("fetch by id returns matching exercise")
    @MainActor
    func fetchById() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Deadlift")
        context.insert(exercise)
        try context.save()

        let repo = SwiftDataExerciseRepository(context: context)
        let fetched = try await repo.fetch(id: exercise.id)
        #expect(fetched?.name == "Deadlift")
    }

    @Test("fetch by id returns nil for unknown id")
    @MainActor
    func fetchByIdMissing() async throws {
        let container = try makeTestContainer()
        let repo = SwiftDataExerciseRepository(context: container.mainContext)
        let result = try await repo.fetch(id: UUID())
        #expect(result == nil)
    }

    @Test("search returns matching exercises by name")
    @MainActor
    func searchByName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(TestFixtures.makeExercise(name: "Bench Press"))
        context.insert(TestFixtures.makeExercise(name: "Incline Bench Press"))
        context.insert(TestFixtures.makeExercise(name: "Squat"))
        try context.save()

        let repo = SwiftDataExerciseRepository(context: context)
        let results = try await repo.search(query: "bench")
        #expect(results.count == 2)
    }

    @Test("search is case-insensitive")
    @MainActor
    func searchCaseInsensitive() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(TestFixtures.makeExercise(name: "Deadlift"))
        try context.save()

        let repo = SwiftDataExerciseRepository(context: context)
        let results = try await repo.search(query: "DEAD")
        #expect(results.count == 1)
    }

    @Test("filter by category and value returns matching exercises")
    @MainActor
    func filterByTag() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let bench = TestFixtures.makeExercise(name: "Bench Press", equipment: "barbell")
        let tag = ExerciseTag(category: "equipment", value: "barbell")
        context.insert(bench)
        context.insert(tag)
        bench.tags.append(tag)

        let dumbbell = TestFixtures.makeExercise(name: "DB Curl", equipment: "dumbbell")
        let tag2 = ExerciseTag(category: "equipment", value: "dumbbell")
        context.insert(dumbbell)
        context.insert(tag2)
        dumbbell.tags.append(tag2)

        try context.save()

        let repo = SwiftDataExerciseRepository(context: context)
        let results = try await repo.filter(category: "equipment", value: "barbell")
        #expect(results.count == 1)
        #expect(results[0].name == "Bench Press")
    }

    @Test("save persists a new exercise")
    @MainActor
    func saveNew() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataExerciseRepository(context: context)
        let exercise = TestFixtures.makeExercise(name: "Pull-up", isCustom: true)
        try await repo.save(exercise)

        let fetched = try await repo.fetchAll()
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Pull-up")
    }

    @Test("delete removes exercise")
    @MainActor
    func deleteExercise() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Push-up")
        context.insert(exercise)
        try context.save()

        let repo = SwiftDataExerciseRepository(context: context)
        try await repo.delete(exercise)

        let fetched = try await repo.fetchAll()
        #expect(fetched.isEmpty)
    }

    @Test("fetchByExternalId returns matching exercise")
    @MainActor
    func fetchByExternalId() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Bench Press", externalId: "bench_press")
        context.insert(exercise)
        try context.save()

        let repo = SwiftDataExerciseRepository(context: context)
        let found = try await repo.fetchByExternalId("bench_press")
        #expect(found?.name == "Bench Press")
    }
}
