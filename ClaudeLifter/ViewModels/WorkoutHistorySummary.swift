import Foundation

/// What a finished workout actually contained, for History (#176).
///
/// A template plans every exercise with its sets, so a workout where three
/// of nine exercises were done still holds nine exercises. Counting those
/// read "9 exercises · 9 sets" for a session of 3 exercises. Only completed
/// sets count here, and an exercise counts only if one of its sets does.
struct WorkoutHistorySummary: Equatable, Sendable {
    let completedExercises: Int
    let skippedExercises: Int
    let completedSets: Int
    /// Completed sets' weight × reps, each set converted from its own unit.
    let volumeKg: Double
    /// Nil while the workout is unfinished.
    let durationMinutes: Int?

    @MainActor
    init(_ workout: Workout) {
        let done = workout.exercises.filter { !Self.isSkipped($0) }
        completedExercises = done.count
        skippedExercises = workout.exercises.count - done.count
        let sets = workout.exercises.flatMap(\.sets).filter(\.isCompleted)
        completedSets = sets.count
        volumeKg = sets.reduce(0) { total, set in
            guard let kilograms = set.weightInKilograms, let reps = set.reps else { return total }
            return total + kilograms * Double(reps)
        }
        durationMinutes = workout.completedAt.map {
            max(0, Int($0.timeIntervalSince(workout.startedAt) / 60))
        }
    }

    /// True when none of the exercise's sets was logged.
    @MainActor
    static func isSkipped(_ exercise: WorkoutExercise) -> Bool {
        !exercise.sets.contains(where: \.isCompleted)
    }

    /// "3 exercises · 9 sets".
    var rowDetail: String {
        let exercises = completedExercises == 1 ? "1 exercise" : "\(completedExercises) exercises"
        let sets = completedSets == 1 ? "1 set" : "\(completedSets) sets"
        return "\(exercises) · \(sets)"
    }

    /// "45 min", or "—" for an unfinished workout.
    var durationText: String {
        durationMinutes.map { "\($0) min" } ?? "—"
    }

    /// "4,320 kg" in the user's unit.
    func volumeText(in unit: WeightUnit) -> String {
        let value = WeightUnit.kg.convert(volumeKg, to: unit)
        return "\(value.formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)"
    }
}
