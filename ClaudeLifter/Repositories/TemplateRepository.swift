import Foundation
import SwiftData

@MainActor
protocol TemplateRepository {
    func fetchAll() async throws -> [WorkoutTemplate]
    func fetch(id: UUID) async throws -> WorkoutTemplate?
    func save(_ template: WorkoutTemplate) async throws
    func delete(_ template: WorkoutTemplate) async throws
}

@MainActor
final class SwiftDataTemplateRepository: TemplateRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [WorkoutTemplate] {
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> WorkoutTemplate? {
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func save(_ template: WorkoutTemplate) async throws {
        context.insert(template)
        try context.save()
    }

    func delete(_ template: WorkoutTemplate) async throws {
        context.delete(template)
        try context.save()
    }
}
