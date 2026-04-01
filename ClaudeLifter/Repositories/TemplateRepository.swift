import Foundation
import SwiftData

@MainActor
protocol TemplateRepository {
    func fetchAll() async throws -> [WorkoutTemplate]
    func fetch(id: UUID) async throws -> WorkoutTemplate?
    func fetchPending() async throws -> [WorkoutTemplate]
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

    func fetchPending() async throws -> [WorkoutTemplate] {
        let all = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        return all.filter { $0.syncStatus == .pending }
    }

    func save(_ template: WorkoutTemplate) async throws {
        context.insert(template)
        for exercise in template.exercises {
            context.insert(exercise)
        }
        try context.save()
    }

    func delete(_ template: WorkoutTemplate) async throws {
        context.delete(template)
        try context.save()
    }
}
