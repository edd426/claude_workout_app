import Foundation
import SwiftData

@MainActor
protocol ExerciseAlternativeRepository {
    func fetchAll() async throws -> [ExerciseAlternative]
    func fetch(id: UUID) async throws -> ExerciseAlternative?
    /// One template exercise's alternatives, by `order`.
    func alternatives(forTemplateExercise templateExerciseId: UUID) async throws -> [ExerciseAlternative]
    /// Full replace: afterwards the template exercise lists exactly `specs`,
    /// in that order (renumbered from 0). An empty list clears it.
    @discardableResult
    func replaceAlternatives(
        forTemplateExercise templateExerciseId: UUID,
        with specs: [AlternativeSpec]
    ) async throws -> [ExerciseAlternative]
    /// Deletes alternatives whose template exercise is in no template.
    /// Returns how many were removed.
    @discardableResult
    func removeOrphans() async throws -> Int
    func fetchPending() async throws -> [ExerciseAlternative]
    /// Inserts one row as is — for restore and import.
    func save(_ alternative: ExerciseAlternative) async throws
    func delete(_ alternative: ExerciseAlternative) async throws
}

@MainActor
final class SwiftDataExerciseAlternativeRepository: ExerciseAlternativeRepository {
    private let context: ModelContext
    /// A removal leaves no `.pending` row to trigger a push, so the owner
    /// passes `settings.markSnapshotDirty` here (see DependencyContainer).
    private let onDeletion: @MainActor () -> Void

    init(context: ModelContext, onDeletion: @escaping @MainActor () -> Void = {}) {
        self.context = context
        self.onDeletion = onDeletion
    }

    func fetchAll() async throws -> [ExerciseAlternative] {
        let descriptor = FetchDescriptor<ExerciseAlternative>(
            sortBy: [SortDescriptor(\.order, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> ExerciseAlternative? {
        let descriptor = FetchDescriptor<ExerciseAlternative>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func alternatives(forTemplateExercise templateExerciseId: UUID) async throws -> [ExerciseAlternative] {
        let descriptor = FetchDescriptor<ExerciseAlternative>(
            predicate: #Predicate { $0.templateExerciseId == templateExerciseId },
            sortBy: [SortDescriptor(\.order, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    @discardableResult
    func replaceAlternatives(
        forTemplateExercise templateExerciseId: UUID,
        with specs: [AlternativeSpec]
    ) async throws -> [ExerciseAlternative] {
        let existing = try await alternatives(forTemplateExercise: templateExerciseId)
        for alternative in existing {
            context.delete(alternative)
        }
        let created = specs.enumerated().map { index, spec in
            ExerciseAlternative(
                templateExerciseId: templateExerciseId,
                externalId: spec.externalId,
                order: index,
                note: spec.note
            )
        }
        for alternative in created {
            context.insert(alternative)
        }
        try context.save()
        if !existing.isEmpty {
            onDeletion()
        }
        return created
    }

    @discardableResult
    func removeOrphans() async throws -> Int {
        let removed = try Self.removeOrphans(in: context)
        if removed > 0 {
            try context.save()
            onDeletion()
        }
        return removed
    }

    /// Shared with `SwiftDataTemplateRepository`, which runs it on every
    /// template save and delete. Deletes but does not save.
    ///
    /// "Orphan" means the template exercise is referenced by NO template —
    /// not merely that its row is gone. Replacing `template.exercises` leaves
    /// the old `TemplateExercise` rows in the store, detached (there is no
    /// inverse), so a row-exists check would keep their alternatives forever.
    static func removeOrphans(in context: ModelContext) throws -> Int {
        let alternatives = try context.fetch(FetchDescriptor<ExerciseAlternative>())
        guard !alternatives.isEmpty else { return 0 }
        let liveIds = Set(
            try context.fetch(FetchDescriptor<WorkoutTemplate>())
                .filter { !$0.isDeleted }
                .flatMap { $0.exercises.map(\.id) }
        )
        var removed = 0
        for alternative in alternatives where !liveIds.contains(alternative.templateExerciseId) {
            context.delete(alternative)
            removed += 1
        }
        return removed
    }

    func fetchPending() async throws -> [ExerciseAlternative] {
        let pendingRaw = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<ExerciseAlternative>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        return try context.fetch(descriptor)
    }

    func save(_ alternative: ExerciseAlternative) async throws {
        context.insert(alternative)
        try context.save()
    }

    func delete(_ alternative: ExerciseAlternative) async throws {
        context.delete(alternative)
        try context.save()
        onDeletion()
    }
}
