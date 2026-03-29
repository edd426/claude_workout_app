import Foundation
import SwiftData

protocol ExerciseRepository: Sendable {
    func fetchAll() async throws -> [Exercise]
    func fetch(id: UUID) async throws -> Exercise?
    func fetchByExternalId(_ externalId: String) async throws -> Exercise?
    func search(query: String) async throws -> [Exercise]
    func filter(category: String, value: String) async throws -> [Exercise]
    func save(_ exercise: Exercise) async throws
    func delete(_ exercise: Exercise) async throws
}

final class SwiftDataExerciseRepository: ExerciseRepository, @unchecked Sendable {
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

    func save(_ exercise: Exercise) async throws {
        context.insert(exercise)
        try context.save()
    }

    func delete(_ exercise: Exercise) async throws {
        context.delete(exercise)
        try context.save()
    }
}
