import Foundation
@testable import ClaudeLifter

@MainActor
final class MockExerciseAlternativeRepository: ExerciseAlternativeRepository {
    var alternatives: [ExerciseAlternative] = []
    var alternativesCallCount = 0
    var errorToThrow: Error?

    func fetchAll() async throws -> [ExerciseAlternative] {
        if let errorToThrow { throw errorToThrow }
        return alternatives.sorted { $0.order < $1.order }
    }

    func fetch(id: UUID) async throws -> ExerciseAlternative? {
        if let errorToThrow { throw errorToThrow }
        return alternatives.first { $0.id == id }
    }

    func alternatives(forTemplateExercise templateExerciseId: UUID) async throws -> [ExerciseAlternative] {
        alternativesCallCount += 1
        if let errorToThrow { throw errorToThrow }
        return alternatives
            .filter { $0.templateExerciseId == templateExerciseId }
            .sorted { $0.order < $1.order }
    }

    @discardableResult
    func replaceAlternatives(
        forTemplateExercise templateExerciseId: UUID,
        with specs: [AlternativeSpec]
    ) async throws -> [ExerciseAlternative] {
        if let errorToThrow { throw errorToThrow }
        alternatives.removeAll { $0.templateExerciseId == templateExerciseId }
        let created = specs.enumerated().map { index, spec in
            ExerciseAlternative(
                templateExerciseId: templateExerciseId,
                externalId: spec.externalId,
                order: index,
                note: spec.note
            )
        }
        alternatives.append(contentsOf: created)
        return created
    }

    @discardableResult
    func removeOrphans() async throws -> Int { 0 }

    func fetchPending() async throws -> [ExerciseAlternative] {
        alternatives.filter { $0.syncStatus == .pending }
    }

    func save(_ alternative: ExerciseAlternative) async throws {
        if let errorToThrow { throw errorToThrow }
        alternatives.append(alternative)
    }

    func delete(_ alternative: ExerciseAlternative) async throws {
        if let errorToThrow { throw errorToThrow }
        alternatives.removeAll { $0.id == alternative.id }
    }
}
