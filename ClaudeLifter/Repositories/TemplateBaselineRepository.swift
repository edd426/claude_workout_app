import Foundation
import SwiftData

/// Storage for the frozen template plan a workout started from (#128).
///
/// Baselines are written once, at workout start, and only ever read after —
/// there is no update path on purpose. A snapshot that can be edited is not a
/// snapshot, and the whole value of it is that ordinary workout mutations
/// cannot reach it.
@MainActor
protocol TemplateBaselineRepository {
    func fetchBaseline(workoutId: UUID) async throws -> WorkoutTemplateBaseline?
    func fetchEntries(workoutId: UUID) async throws -> [WorkoutExerciseBaseline]
    func save(
        _ baseline: WorkoutTemplateBaseline,
        entries: [WorkoutExerciseBaseline]
    ) async throws
    func delete(workoutId: UUID) async throws
}

@MainActor
final class SwiftDataTemplateBaselineRepository: TemplateBaselineRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchBaseline(workoutId: UUID) async throws -> WorkoutTemplateBaseline? {
        let descriptor = FetchDescriptor<WorkoutTemplateBaseline>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )
        return try context.fetch(descriptor).first
    }

    func fetchEntries(workoutId: UUID) async throws -> [WorkoutExerciseBaseline] {
        let descriptor = FetchDescriptor<WorkoutExerciseBaseline>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.plannedOrder)]
        )
        return try context.fetch(descriptor)
    }

    func save(
        _ baseline: WorkoutTemplateBaseline,
        entries: [WorkoutExerciseBaseline]
    ) async throws {
        context.insert(baseline)
        for entry in entries {
            context.insert(entry)
        }
        try context.save()
    }

    /// Used when a workout is discarded — an empty ghost session, or a cancel.
    /// A baseline for a workout that no longer exists is orphaned data that
    /// nothing will ever collect.
    func delete(workoutId: UUID) async throws {
        for entry in try await fetchEntries(workoutId: workoutId) {
            context.delete(entry)
        }
        if let baseline = try await fetchBaseline(workoutId: workoutId) {
            context.delete(baseline)
        }
        try context.save()
    }
}
