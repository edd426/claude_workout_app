import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("TemplateRepository Tests")
struct TemplateRepositoryTests {
    @Test("fetchAll returns empty when no templates")
    @MainActor
    func fetchAllEmpty() async throws {
        let container = try makeTestContainer()
        let repo = SwiftDataTemplateRepository(context: container.mainContext)
        let results = try await repo.fetchAll()
        #expect(results.isEmpty)
    }

    @Test("fetchAll returns templates sorted by name")
    @MainActor
    func fetchAllSorted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(WorkoutTemplate(name: "Z Template"))
        context.insert(WorkoutTemplate(name: "A Template"))
        try context.save()

        let repo = SwiftDataTemplateRepository(context: context)
        let results = try await repo.fetchAll()
        #expect(results.count == 2)
        #expect(results[0].name == "A Template")
    }

    @Test("fetch by id returns correct template")
    @MainActor
    func fetchById() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "Push Day")
        context.insert(template)
        try context.save()

        let repo = SwiftDataTemplateRepository(context: context)
        let found = try await repo.fetch(id: template.id)
        #expect(found?.name == "Push Day")
    }

    @Test("fetch by id returns nil for unknown id")
    @MainActor
    func fetchByIdMissing() async throws {
        let container = try makeTestContainer()
        let repo = SwiftDataTemplateRepository(context: container.mainContext)
        let result = try await repo.fetch(id: UUID())
        #expect(result == nil)
    }

    @Test("save persists a new template")
    @MainActor
    func saveTemplate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataTemplateRepository(context: context)
        let template = WorkoutTemplate(name: "Leg Day")
        try await repo.save(template)

        let results = try await repo.fetchAll()
        #expect(results.count == 1)
        #expect(results[0].name == "Leg Day")
    }

    @Test("delete removes template")
    @MainActor
    func deleteTemplate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "Upper Body")
        context.insert(template)
        try context.save()

        let repo = SwiftDataTemplateRepository(context: context)
        try await repo.delete(template)

        let results = try await repo.fetchAll()
        #expect(results.isEmpty)
    }

    @Test("save template with pre-built exercises persists exercises")
    @MainActor
    func saveTemplateWithExercisesPersistsExercises() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Arrange: create Exercise objects in context first (needed as foreign keys)
        let exercise1 = Exercise(name: "Bench Press")
        let exercise2 = Exercise(name: "Overhead Press")
        context.insert(exercise1)
        context.insert(exercise2)
        try context.save()

        // Create template with TemplateExercise children but do NOT manually insert
        // the TemplateExercise objects — only the parent is passed to repo.save().
        // This simulates how Claude-generated templates are built and handed to the repo.
        let template = WorkoutTemplate(name: "Push Day")
        let te1 = TemplateExercise(order: 0, exercise: exercise1, defaultSets: 3, defaultReps: 8)
        let te2 = TemplateExercise(order: 1, exercise: exercise2, defaultSets: 4, defaultReps: 10)
        template.exercises.append(te1)
        template.exercises.append(te2)

        let repo = SwiftDataTemplateRepository(context: context)

        // Act: only the template is explicitly saved; exercises must be inserted by the repo
        try await repo.save(template)

        // Assert: fetching back by ID should show both TemplateExercise children
        let fetched = try await repo.fetch(id: template.id)
        #expect(fetched != nil)
        #expect(fetched?.exercises.count == 2)
    }

    @Test("save template exercises are queryable after re-fetch")
    @MainActor
    func saveTemplateExercisesQueryableAfterReFetch() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Arrange: exercises in context
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)
        try context.save()

        // Build template with 3 TemplateExercise children
        let template = WorkoutTemplate(name: "Leg Day")
        for i in 0..<3 {
            let te = TemplateExercise(order: i, exercise: exercise, defaultSets: 3, defaultReps: 5)
            template.exercises.append(te)
        }

        let repo = SwiftDataTemplateRepository(context: context)
        try await repo.save(template)

        // Fetch all TemplateExercise objects directly to confirm they are in the store
        let allTEs = try context.fetch(FetchDescriptor<TemplateExercise>())
        #expect(allTEs.count == 3)
    }
}
