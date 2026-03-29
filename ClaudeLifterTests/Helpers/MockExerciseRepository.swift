import Foundation
@testable import ClaudeLifter

@MainActor
final class MockExerciseRepository: ExerciseRepository {
    var exercises: [Exercise] = []
    var searchResults: [Exercise] = []
    var filterResults: [Exercise] = []
    var savedExercises: [Exercise] = []
    var fetchAllCallCount = 0
    var searchCallCount = 0
    var lastSearchQuery: String = ""
    var errorToThrow: Error? = nil

    func fetchAll() async throws -> [Exercise] {
        fetchAllCallCount += 1
        if let error = errorToThrow { throw error }
        return exercises
    }

    func fetch(id: UUID) async throws -> Exercise? {
        if let error = errorToThrow { throw error }
        return exercises.first { $0.id == id }
    }

    func fetchByExternalId(_ externalId: String) async throws -> Exercise? {
        if let error = errorToThrow { throw error }
        return exercises.first { $0.externalId == externalId }
    }

    func search(query: String) async throws -> [Exercise] {
        searchCallCount += 1
        lastSearchQuery = query
        if let error = errorToThrow { throw error }
        if searchResults.isEmpty {
            return exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return searchResults
    }

    func filter(category: String, value: String) async throws -> [Exercise] {
        if let error = errorToThrow { throw error }
        if !filterResults.isEmpty { return filterResults }
        return exercises.filter { ex in
            ex.tags.contains { $0.category == category && $0.value == value }
        }
    }

    func save(_ exercise: Exercise) async throws {
        if let error = errorToThrow { throw error }
        savedExercises.append(exercise)
        if !exercises.contains(where: { $0.id == exercise.id }) {
            exercises.append(exercise)
        }
    }

    func delete(_ exercise: Exercise) async throws {
        if let error = errorToThrow { throw error }
        exercises.removeAll { $0.id == exercise.id }
    }
}
