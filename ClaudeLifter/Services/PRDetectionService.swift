import Foundation

@MainActor
protocol PRDetectionServiceProtocol {
    func detectPRs(for workout: Workout) async throws -> [PersonalRecord]
    func getAllPRs(for exerciseId: UUID) async throws -> [PersonalRecord]
}

@MainActor
final class PRDetectionService: PRDetectionServiceProtocol {
    private let prRepository: PersonalRecordRepository

    init(prRepository: PersonalRecordRepository) {
        self.prRepository = prRepository
    }

    func detectPRs(for workout: Workout) async throws -> [PersonalRecord] {
        var newPRs: [PersonalRecord] = []

        for workoutExercise in workout.exercises {
            guard let exercise = workoutExercise.exercise else { continue }
            let completedSets = workoutExercise.sets.filter { $0.isCompleted }
            guard !completedSets.isEmpty else { continue }

            let exerciseId = exercise.id
            let existingPRs = try await prRepository.fetch(exerciseId: exerciseId)

            let existingHeaviestWeight = existingPRs.first { $0.prType == .heaviestWeight }?.value
            let existingHighest1RM = existingPRs.first { $0.prType == .highest1RM }?.value

            // Track the best values found in this workout for this exercise
            var bestWeight: Double? = nil
            var best1RM: Double? = nil

            // mostRepsAtWeight is tracked per weight
            // key: weight value, value: max reps seen in existing PRs
            var existingRepsAtWeight: [Double: Int] = [:]
            for pr in existingPRs where pr.prType == .mostRepsAtWeight {
                if let w = pr.weight {
                    let current = existingRepsAtWeight[w] ?? 0
                    existingRepsAtWeight[w] = max(current, pr.reps ?? 0)
                }
            }

            // Track best reps at weight found in this workout
            var bestRepsAtWeight: [Double: (reps: Int, set: WorkoutSet)] = [:]

            for set in completedSets {
                guard let weight = set.weight, let reps = set.reps, weight > 0 else { continue }

                // Heaviest weight
                if bestWeight == nil || weight > bestWeight! {
                    bestWeight = weight
                }

                // Most reps at this weight
                let existingReps = existingRepsAtWeight[weight] ?? 0
                if reps > existingReps {
                    if let current = bestRepsAtWeight[weight] {
                        if reps > current.reps {
                            bestRepsAtWeight[weight] = (reps, set)
                        }
                    } else {
                        bestRepsAtWeight[weight] = (reps, set)
                    }
                }

                // Highest estimated 1RM
                if let oneRM = PersonalRecord.estimated1RM(weight: weight, reps: reps) {
                    if best1RM == nil || oneRM > best1RM! {
                        best1RM = oneRM
                    }
                }
            }

            // Save heaviest weight PR if it beats existing
            if let weight = bestWeight {
                if existingHeaviestWeight == nil || weight > existingHeaviestWeight! {
                    let pr = PersonalRecord(
                        exerciseId: exerciseId,
                        type: .heaviestWeight,
                        value: weight,
                        weight: weight,
                        achievedAt: .now,
                        workoutId: workout.id
                    )
                    try await prRepository.save(pr)
                    newPRs.append(pr)
                }
            }

            // Save most reps at weight PRs
            for (weight, entry) in bestRepsAtWeight {
                let pr = PersonalRecord(
                    exerciseId: exerciseId,
                    type: .mostRepsAtWeight,
                    value: Double(entry.reps),
                    weight: weight,
                    reps: entry.reps,
                    achievedAt: .now,
                    workoutId: workout.id
                )
                try await prRepository.save(pr)
                newPRs.append(pr)
            }

            // Save highest 1RM PR if it beats existing
            if let oneRM = best1RM {
                if existingHighest1RM == nil || oneRM > existingHighest1RM! {
                    let pr = PersonalRecord(
                        exerciseId: exerciseId,
                        type: .highest1RM,
                        value: oneRM,
                        achievedAt: .now,
                        workoutId: workout.id
                    )
                    try await prRepository.save(pr)
                    newPRs.append(pr)
                }
            }
        }

        return newPRs
    }

    func getAllPRs(for exerciseId: UUID) async throws -> [PersonalRecord] {
        try await prRepository.fetch(exerciseId: exerciseId)
    }
}
