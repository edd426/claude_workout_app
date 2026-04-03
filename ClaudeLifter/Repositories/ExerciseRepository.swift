import Foundation
import SwiftData

@MainActor
protocol ExerciseRepository {
    func fetchAll() async throws -> [Exercise]
    func fetch(id: UUID) async throws -> Exercise?
    func fetchByExternalId(_ externalId: String) async throws -> Exercise?
    func search(query: String) async throws -> [Exercise]
    /// Flexible search: tries exact contains first, then falls back to word-based matching.
    /// This handles Claude outputting "Barbell Squat" when DB has "Squat" or "Barbell Full Squat".
    func fuzzySearch(query: String) async throws -> [Exercise]
    func filter(category: String, value: String) async throws -> [Exercise]
    func fetchDistinctTagCategories() async throws -> [String]
    func fetchDistinctTagValues(for category: String) async throws -> [String]
    func save(_ exercise: Exercise) async throws
    func delete(_ exercise: Exercise) async throws
}

@MainActor
final class SwiftDataExerciseRepository: ExerciseRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetchByExternalId(_ externalId: String) async throws -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.externalId == externalId }
        )
        return try context.fetch(descriptor).first
    }

    func search(query: String) async throws -> [Exercise] {
        let lowercased = query.lowercased()
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.name.localizedStandardContains(lowercased) },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fuzzySearch(query: String) async throws -> [Exercise] {
        // Pass 1: standard contains (fast, handles most cases)
        let standardResults = try await search(query: query)
        if !standardResults.isEmpty { return standardResults }

        // Pass 2: word-based — search for each significant word, union candidates, score by match count
        let words = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 } // skip "the", "a", etc.

        guard !words.isEmpty else { return [] }

        // Search for every significant word and union the candidate sets
        var seenIds = Set<UUID>()
        var candidates: [Exercise] = []
        for word in words {
            let results = try await search(query: word)
            for exercise in results where !seenIds.contains(exercise.id) {
                seenIds.insert(exercise.id)
                candidates.append(exercise)
            }
        }

        // Score candidates by how many query words appear in the exercise name
        let scored = candidates.map { exercise -> (Exercise, Int) in
            let name = exercise.name.lowercased()
            let matchCount = words.filter { name.contains($0) }.count
            return (exercise, matchCount)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 } // best matches first

        return scored.map(\.0)
    }

    func filter(category: String, value: String) async throws -> [Exercise] {
        let all = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))
        return all.filter { exercise in
            exercise.tags.contains { tag in
                tag.category == category && tag.value == value
            }
        }
    }

    func fetchDistinctTagCategories() async throws -> [String] {
        let tags = try context.fetch(FetchDescriptor<ExerciseTag>())
        return Array(Set(tags.map(\.category))).sorted()
    }

    func fetchDistinctTagValues(for category: String) async throws -> [String] {
        let descriptor = FetchDescriptor<ExerciseTag>(
            predicate: #Predicate { $0.category == category }
        )
        let tags = try context.fetch(descriptor)
        return Array(Set(tags.map(\.value))).sorted()
    }

    func save(_ exercise: Exercise) async throws {
        context.insert(exercise)
        try context.save()
    }

    func delete(_ exercise: Exercise) async throws {
        context.delete(exercise)
        try context.save()
    }
}
