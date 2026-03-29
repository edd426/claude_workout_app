import Foundation

struct AutoFillResult: Sendable {
    let weight: Double?
    let weightUnit: WeightUnit
    let reps: Int?
    let date: Date
}

@MainActor
protocol AutoFillServiceProtocol {
    func lastPerformed(exerciseId: UUID) async throws -> AutoFillResult?
}

@MainActor
final class AutoFillService: AutoFillServiceProtocol {
    private let workoutRepository: any WorkoutRepository

    init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    func lastPerformed(exerciseId: UUID) async throws -> AutoFillResult? {
        // lastSessionSets returns completed sets from the most recent workout containing
        // the exercise, sorted by order ascending. We take the last (highest order) set
        // as the auto-fill value (the "working set" the user finished with).
        let sets = try await workoutRepository.lastSessionSets(for: exerciseId)
        guard let lastSet = sets.last, let completedAt = lastSet.completedAt else {
            return nil
        }
        return AutoFillResult(
            weight: lastSet.weight,
            weightUnit: lastSet.weightUnit,
            reps: lastSet.reps,
            date: completedAt
        )
    }
}
