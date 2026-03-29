import Foundation
@testable import ClaudeLifter

final class MockTemplateRepository: TemplateRepository, @unchecked Sendable {
    var templates: [WorkoutTemplate] = []
    var savedTemplates: [WorkoutTemplate] = []
    var deletedTemplates: [WorkoutTemplate] = []
    var fetchAllCallCount = 0
    var saveCallCount = 0
    var deleteCallCount = 0
    var errorToThrow: Error? = nil

    func fetchAll() async throws -> [WorkoutTemplate] {
        fetchAllCallCount += 1
        if let error = errorToThrow { throw error }
        return templates
    }

    func fetch(id: UUID) async throws -> WorkoutTemplate? {
        if let error = errorToThrow { throw error }
        return templates.first { $0.id == id }
    }

    func save(_ template: WorkoutTemplate) async throws {
        saveCallCount += 1
        if let error = errorToThrow { throw error }
        savedTemplates.append(template)
        if !templates.contains(where: { $0.id == template.id }) {
            templates.append(template)
        }
    }

    func delete(_ template: WorkoutTemplate) async throws {
        deleteCallCount += 1
        if let error = errorToThrow { throw error }
        deletedTemplates.append(template)
        templates.removeAll { $0.id == template.id }
    }
}
