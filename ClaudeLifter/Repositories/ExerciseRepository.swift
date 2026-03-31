import Foundation
import SwiftData

@MainActor
protocol ExerciseRepository {
    func fetchAll() async throws -> [Exercise]
    func fetch(id: UUID) async throws -> Exercise?
    func fetchByExternalId(_ externalId: String) async throws -> Exercise?
    func search(query: String) async throws -> [Exercise]
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
