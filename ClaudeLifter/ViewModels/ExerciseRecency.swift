import Foundation

/// What the active-workout card's "last done" panel shows (issue #167): when
/// this exercise was last done, with that session's sets, and when each of
/// its primary muscles was last trained by any exercise.
///
/// Value types only: the panel can hold one across a SwiftData save or a
/// deletion elsewhere without touching a model object that may be gone.
struct ExerciseRecency: Equatable, Sendable {
    struct SetSummary: Equatable, Sendable {
        /// Nil means bodyweight.
        let weight: Double?
        let unit: WeightUnit
        let reps: Int?
    }

    struct Session: Equatable, Sendable {
        let date: Date
        let workoutName: String
        let sets: [SetSummary]
    }

    struct Muscle: Equatable, Sendable {
        let name: String
        /// Time of the latest completed set of an exercise with this muscle as
        /// a primary; nil means never.
        let lastTrained: Date?
        let viaExercise: String?
        /// Completed sets since the start of this week in finished workouts: a
        /// set counts 1 when the muscle is primary, 0.5 when it is secondary.
        let setsThisWeek: Double
    }

    /// Nil means never done in a finished workout.
    let lastSession: Session?
    let muscles: [Muscle]

    /// "Today", "Yesterday", "6 days ago", "3 weeks ago", "5 months ago",
    /// "2 years ago" — by calendar day, so 23:00 yesterday is "Yesterday".
    static func relativeDay(_ date: Date?, now: Date, calendar: Calendar) -> String {
        guard let date else { return "Never" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        case 60..<730: return "\(days / 30) months ago"
        default: return "\(days / 365) years ago"
        }
    }

    /// "60 × 8, 65 × 6 kg". One trailing unit when every weighted set shares
    /// it; otherwise each set carries its own. Bodyweight sets read "BW".
    static func summary(of sets: [SetSummary]) -> String {
        let weightedUnits = Set(sets.filter { $0.weight != nil }.map(\.unit))
        let sharedUnit = weightedUnits.count == 1 ? weightedUnits.first : nil
        let parts = sets.map { set -> String in
            let reps = set.reps.map(String.init) ?? "–"
            guard let weight = set.weight else { return "BW × \(reps)" }
            let number = weight.formatted(
                .number.grouping(.never).precision(.fractionLength(0...2))
            )
            return sharedUnit == nil
                ? "\(number) \(set.unit.rawValue) × \(reps)"
                : "\(number) × \(reps)"
        }
        let joined = parts.joined(separator: ", ")
        guard let sharedUnit else { return joined }
        return "\(joined) \(sharedUnit.rawValue)"
    }
}

/// Builds `ExerciseRecency` from workout history. Only finished workouts
/// count, and the in-progress one is excluded by id as well, so the panel
/// describes what came before this session.
enum ExerciseRecencyCalculator {
    @MainActor
    static func recency(
        for exercise: Exercise,
        history: [Workout],
        excludingWorkoutId: UUID?,
        now: Date,
        calendar: Calendar
    ) -> ExerciseRecency {
        let finished = history
            .filter { $0.completedAt != nil && $0.id != excludingWorkoutId }
            .sorted { $0.startedAt > $1.startedAt }
        let muscles = uniqueMuscles(exercise.primaryMuscles)
        let weekly = weeklySets(for: muscles, in: finished, now: now, calendar: calendar)
        let trained = lastTrained(muscles, in: finished)
        return ExerciseRecency(
            lastSession: lastSession(of: exercise, in: finished),
            muscles: muscles.map { muscle in
                ExerciseRecency.Muscle(
                    name: muscle,
                    lastTrained: trained[muscle]?.date,
                    viaExercise: trained[muscle]?.exercise,
                    setsThisWeek: weekly[muscle] ?? 0
                )
            }
        )
    }

    private static func normalized(_ muscle: String) -> String {
        muscle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func uniqueMuscles(_ muscles: [String]) -> [String] {
        var seen = Set<String>()
        return muscles.map(normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Newest finished workout with at least one completed set of the exercise.
    @MainActor
    private static func lastSession(
        of exercise: Exercise,
        in finished: [Workout]
    ) -> ExerciseRecency.Session? {
        for workout in finished {
            let sets = workout.exercises
                .filter { $0.exercise?.id == exercise.id }
                .sorted { $0.order < $1.order }
                .flatMap { $0.sets.sorted { $0.order < $1.order } }
                .filter(\.isCompleted)
            guard !sets.isEmpty else { continue }
            return ExerciseRecency.Session(
                date: workout.startedAt,
                workoutName: workout.name,
                sets: sets.map {
                    ExerciseRecency.SetSummary(weight: $0.weight, unit: $0.weightUnit, reps: $0.reps)
                }
            )
        }
        return nil
    }

    /// For each muscle, the latest completed set of any exercise that lists it
    /// as a primary muscle. Walks newest-first and stops once every muscle is
    /// found; within one workout the latest set wins.
    @MainActor
    private static func lastTrained(
        _ muscles: [String],
        in finished: [Workout]
    ) -> [String: (date: Date, exercise: String)] {
        var found: [String: (date: Date, exercise: String)] = [:]
        for workout in finished {
            if found.count == muscles.count { break }
            var inWorkout: [String: (date: Date, exercise: String)] = [:]
            for workoutExercise in workout.exercises {
                guard let exercise = workoutExercise.exercise else { continue }
                let primaries = Set(exercise.primaryMuscles.map(normalized))
                let hits = muscles.filter { found[$0] == nil && primaries.contains($0) }
                guard !hits.isEmpty else { continue }
                let latestSet = workoutExercise.sets
                    .filter(\.isCompleted)
                    .map { $0.completedAt ?? workout.completedAt ?? workout.startedAt }
                    .max()
                guard let latestSet else { continue }
                for muscle in hits where (inWorkout[muscle]?.date ?? .distantPast) < latestSet {
                    inWorkout[muscle] = (latestSet, exercise.name)
                }
            }
            found.merge(inWorkout) { existing, _ in existing }
        }
        return found
    }

    /// Completed sets this week per muscle: 1 per set where it is primary,
    /// 0.5 where it is only secondary.
    @MainActor
    private static func weeklySets(
        for muscles: [String],
        in finished: [Workout],
        now: Date,
        calendar: Calendar
    ) -> [String: Double] {
        guard !muscles.isEmpty,
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        else { return [:] }
        var totals: [String: Double] = [:]
        for workout in finished {
            guard workout.startedAt >= weekStart else { break }
            for workoutExercise in workout.exercises {
                guard let exercise = workoutExercise.exercise else { continue }
                let completed = Double(workoutExercise.sets.filter(\.isCompleted).count)
                guard completed > 0 else { continue }
                let primaries = Set(exercise.primaryMuscles.map(normalized))
                let secondaries = Set(exercise.secondaryMuscles.map(normalized))
                for muscle in muscles {
                    if primaries.contains(muscle) {
                        totals[muscle, default: 0] += completed
                    } else if secondaries.contains(muscle) {
                        totals[muscle, default: 0] += completed * 0.5
                    }
                }
            }
        }
        return totals
    }
}
