import Foundation

struct AutoFillResult: Sendable {
    let weight: Double?
    let weightUnit: WeightUnit
    let reps: Int?
    let date: Date
}

@MainActor
protocol AutoFillServiceProtocol {
    /// The final completed set of the most recent session containing the
    /// exercise (the "working set" the user finished with). Nil when the
    /// exercise has no completed history.
    func lastPerformed(exerciseId: UUID) async throws -> AutoFillResult?

    /// Per-set-index auto-fill values for a new session with `setCount` sets,
    /// mapped from the previous session's completed sets (set 1 → set 1,
    /// set 2 → set 2, …) so warm-up → top-set structure is preserved (#82).
    ///
    /// When the counts differ: if the new session has MORE sets than the
    /// previous one, the previous session's last set repeats for the extras;
    /// extra previous sets beyond `setCount` are ignored. Returns exactly
    /// `setCount` elements, or an empty array when there is no completed
    /// history (callers should then fall back to template defaults).
    func autoFillValues(exerciseId: UUID, setCount: Int) async throws -> [AutoFillResult]

    /// The same lookup while excluding an active draft. Resume and
    /// mid-workout additions use this so completed sets from the current
    /// session cannot masquerade as previous-session ghosts.
    func autoFillValues(
        exerciseId: UUID,
        setCount: Int,
        excludingWorkoutId: UUID?
    ) async throws -> [AutoFillResult]
}

extension AutoFillServiceProtocol {
    func autoFillValues(
        exerciseId: UUID,
        setCount: Int,
        excludingWorkoutId: UUID?
    ) async throws -> [AutoFillResult] {
        try await autoFillValues(exerciseId: exerciseId, setCount: setCount)
    }
}

@MainActor
final class AutoFillService: AutoFillServiceProtocol {
    private let workoutRepository: any WorkoutRepository

    init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    func lastPerformed(exerciseId: UUID) async throws -> AutoFillResult? {
        try await previousSessionResults(exerciseId: exerciseId).last
    }

    func autoFillValues(exerciseId: UUID, setCount: Int) async throws -> [AutoFillResult] {
        guard setCount > 0 else { return [] }
        let previous = try await previousSessionResults(exerciseId: exerciseId)
        return mapped(previous, setCount: setCount)
    }

    func autoFillValues(
        exerciseId: UUID,
        setCount: Int,
        excludingWorkoutId: UUID?
    ) async throws -> [AutoFillResult] {
        guard setCount > 0 else { return [] }
        guard let excludingWorkoutId else {
            return try await autoFillValues(
                exerciseId: exerciseId,
                setCount: setCount
            )
        }
        let previous = try await previousSessionResults(
            exerciseId: exerciseId,
            excludingWorkoutId: excludingWorkoutId
        )
        return mapped(previous, setCount: setCount)
    }

    private func mapped(
        _ previous: [AutoFillResult],
        setCount: Int
    ) -> [AutoFillResult] {
        guard !previous.isEmpty else { return [] }
        return (0..<setCount).map { index in
            previous[min(index, previous.count - 1)]
        }
    }

    /// One AutoFillResult per completed set of the most recent session
    /// containing the exercise, in set order. `lastSessionSets` already
    /// filters to completed sets and sorts by order ascending; sets missing a
    /// `completedAt` (data anomaly) are dropped defensively.
    private func previousSessionResults(exerciseId: UUID) async throws -> [AutoFillResult] {
        let sets = try await workoutRepository.lastSessionSets(for: exerciseId)
        return results(from: sets)
    }

    private func previousSessionResults(
        exerciseId: UUID,
        excludingWorkoutId: UUID
    ) async throws -> [AutoFillResult] {
        let workouts = try await workoutRepository.fetchAll()
            .sorted(by: { $0.startedAt > $1.startedAt })
        for workout in workouts where workout.id != excludingWorkoutId {
            guard let workoutExercise = workout.exercises.first(where: {
                $0.exercise?.id == exerciseId
            }) else {
                continue
            }
            let completedSets = workoutExercise.sets
                .filter(\.isCompleted)
                .sorted(by: { $0.order < $1.order })
            if !completedSets.isEmpty {
                return results(from: completedSets)
            }
        }
        return []
    }

    private func results(from sets: [WorkoutSet]) -> [AutoFillResult] {
        sets.compactMap { set in
            guard let completedAt = set.completedAt else { return nil }
            return AutoFillResult(
                weight: set.weight,
                weightUnit: set.weightUnit,
                reps: set.reps,
                date: completedAt
            )
        }
    }
}
