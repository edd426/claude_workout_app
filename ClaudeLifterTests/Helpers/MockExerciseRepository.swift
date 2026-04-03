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
    var distinctCategories: [String] = []
    var distinctValuesByCategory: [String: [String]] = [:]

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

    func fuzzySearch(query: String) async throws -> [Exercise] {
        if let error = errorToThrow { throw error }
        // Try standard contains first
        let standard = exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
        if !standard.isEmpty { return standard }

        // Word-based fallback — union candidates across all significant words
        let words = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !words.isEmpty else { return [] }

        var seenIds = Set<UUID>()
        var candidates: [Exercise] = []
        for word in words {
            for exercise in exercises where !seenIds.contains(exercise.id) && exercise.name.localizedCaseInsensitiveContains(word) {
                seenIds.insert(exercise.id)
                candidates.append(exercise)
            }
        }

        let scored = candidates.map { exercise -> (Exercise, Int) in
            let name = exercise.name.lowercased()
            let matchCount = words.filter { name.contains($0) }.count
            return (exercise, matchCount)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }

        return scored.map(\.0)
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

    func fetchDistinctTagCategories() async throws -> [String] {
        if let error = errorToThrow { throw error }
        return distinctCategories
    }

    func fetchDistinctTagValues(for category: String) async throws -> [String] {
        if let error = errorToThrow { throw error }
        return distinctValuesByCategory[category] ?? []
    }

    func delete(_ exercise: Exercise) async throws {
        if let error = errorToThrow { throw error }
        exercises.removeAll { $0.id == exercise.id }
    }
}
