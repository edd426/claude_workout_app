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
}
