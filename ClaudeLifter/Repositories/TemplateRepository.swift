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
        let pendingRaw = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        return try context.fetch(descriptor)
    }

    func save(_ template: WorkoutTemplate) async throws {
        context.insert(template)
        for exercise in template.exercises {
            context.insert(exercise)
        }
        try context.save()
        try removeOrphanedAlternatives()
    }

    func delete(_ template: WorkoutTemplate) async throws {
        context.delete(template)
        try context.save()
        try removeOrphanedAlternatives()
    }

    /// `ExerciseAlternative` points at its template exercise by plain UUID
    /// (`TemplateExercise` must not gain a property or inverse), so nothing
    /// cascades to it. Any save or delete can drop a template exercise, so
    /// both clean up — after the template's own save, so a failed save never
    /// costs the user their alternatives.
    private func removeOrphanedAlternatives() throws {
        if try SwiftDataExerciseAlternativeRepository.removeOrphans(in: context) > 0 {
            try context.save()
        }
    }
}
