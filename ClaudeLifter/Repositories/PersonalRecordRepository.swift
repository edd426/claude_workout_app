import Foundation
import SwiftData

@MainActor
protocol PersonalRecordRepository {
    func fetchAll() async throws -> [PersonalRecord]
    func fetch(exerciseId: UUID) async throws -> [PersonalRecord]
    func fetchByType(exerciseId: UUID, type: PRType) async throws -> [PersonalRecord]
    func save(_ record: PersonalRecord) async throws
    /// Completed, weighted sets of finished workouts other than
    /// `excludingWorkoutId`, for the exercises in `exerciseIds` or with an
    /// `externalId` in `externalIds`. This is the PR baseline (#173):
    /// stored records alone can't be one, because they aren't mirrored and
    /// they're keyed by exercise UUIDs that change when the catalog is
    /// re-imported, so a restored phone has history but no records.
    func completedSetHistory(
        exerciseIds: Set<UUID>,
        externalIds: Set<String>,
        excludingWorkoutId: UUID
    ) async throws -> [PRHistorySet]
}

@MainActor
final class SwiftDataPersonalRecordRepository: PersonalRecordRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(exerciseId: UUID) async throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try context.fetch(descriptor)
    }

    func fetchByType(exerciseId: UUID, type: PRType) async throws -> [PersonalRecord] {
        let typeRawValue = type.rawValue
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.type == typeRawValue }
        )
        return try context.fetch(descriptor)
    }

    func save(_ record: PersonalRecord) async throws {
        context.insert(record)
        try context.save()
    }

    func completedSetHistory(
        exerciseIds: Set<UUID>,
        externalIds: Set<String>,
        excludingWorkoutId: UUID
    ) async throws -> [PRHistorySet] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.completedAt != nil }
        )
        var history: [PRHistorySet] = []
        for workout in try context.fetch(descriptor) where workout.id != excludingWorkoutId {
            for workoutExercise in workout.exercises {
                guard let exercise = workoutExercise.exercise else { continue }
                let matches = exerciseIds.contains(exercise.id)
                    || exercise.externalId.map(externalIds.contains) == true
                guard matches else { continue }
                for set in workoutExercise.sets where set.isCompleted {
                    // Nil weight is bodyweight; no reps is no set.
                    guard let kilograms = set.weightInKilograms, kilograms > 0,
                          let reps = set.reps, reps > 0
                    else { continue }
                    history.append(PRHistorySet(
                        exerciseId: exercise.id,
                        externalId: exercise.externalId,
                        weightKg: kilograms,
                        reps: reps,
                        date: workout.startedAt
                    ))
                }
            }
        }
        return history
    }
}
