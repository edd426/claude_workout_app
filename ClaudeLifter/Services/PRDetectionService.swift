import Foundation

@MainActor
protocol PRDetectionServiceProtocol {
    /// Detects this workout's records, saves them, and returns them.
    func detectPRs(for workout: Workout) async throws -> [PersonalRecord]
    func getAllPRs(for exerciseId: UUID) async throws -> [PersonalRecord]
    /// The same records with the lifetime best beside each, plus lifetime
    /// bests for exercises done today without a record. Saves nothing. Nil
    /// when a detector can't produce one; callers then show `detectPRs`'
    /// records on their own.
    func prReport(for workout: Workout) async throws -> PRReport?
}

extension PRDetectionServiceProtocol {
    func prReport(for workout: Workout) async throws -> PRReport? { nil }
}

/// Personal records against history (#173).
///
/// The bar is every completed set of the same exercise since `PREra.start`,
/// in finished workouts, matched by `externalId` so a re-imported catalog
/// (new UUIDs) or a restored phone (no stored records) still knows its
/// history. Stored records of the same exercise row count as well. Older
/// sets, such as the Jefit import, are only the lifetime reference.
///
/// Every weight is compared in kilograms, converted from each set's own
/// unit; nothing assumes history was logged in kg.
@MainActor
final class PRDetectionService: PRDetectionServiceProtocol {
    private let prRepository: PersonalRecordRepository
    private let eraStart: Date
    /// The last report, so the summary reading it right after detection
    /// doesn't walk the history twice.
    private var cachedReport: (workoutId: UUID, report: PRReport)?

    init(prRepository: PersonalRecordRepository, eraStart: Date = PREra.start) {
        self.prRepository = prRepository
        self.eraStart = eraStart
    }

    func detectPRs(for workout: Workout) async throws -> [PersonalRecord] {
        let report = try await buildReport(for: workout)
        cachedReport = (workout.id, report)
        var saved: [PersonalRecord] = []
        for record in report.records {
            let row = PersonalRecord(
                exerciseId: record.exerciseId,
                type: record.type,
                value: record.value,
                weight: record.set.weightKg,
                reps: record.set.reps,
                achievedAt: .now,
                workoutId: workout.id
            )
            try await prRepository.save(row)
            saved.append(row)
        }
        return saved
    }

    func getAllPRs(for exerciseId: UUID) async throws -> [PersonalRecord] {
        try await prRepository.fetch(exerciseId: exerciseId)
    }

    func prReport(for workout: Workout) async throws -> PRReport? {
        if let cachedReport, cachedReport.workoutId == workout.id {
            return cachedReport.report
        }
        return try await buildReport(for: workout)
    }

    // MARK: - Building

    private struct ExerciseSets {
        let exercise: Exercise
        var sets: [PRSetRef]
    }

    private func buildReport(for workout: Workout) async throws -> PRReport {
        let exercises = todaysSets(in: workout)
        guard !exercises.isEmpty else { return PRReport() }
        let history = try await prRepository.completedSetHistory(
            exerciseIds: Set(exercises.map(\.exercise.id)),
            externalIds: Set(exercises.compactMap(\.exercise.externalId)),
            excludingWorkoutId: workout.id
        )

        var report = PRReport()
        for entry in exercises {
            let exercise = entry.exercise
            let lifetime = history
                .filter { matches($0, exercise) }
                .map { PRSetRef(weightKg: $0.weightKg, reps: $0.reps, date: $0.date) }
            // A record row saved for this very workout is not an earlier bar.
            let stored = try await prRepository.fetch(exerciseId: exercise.id)
                .filter { $0.workoutId != workout.id }
            let baseline = PRReportBuilder.baseline(
                history: lifetime, storedRecords: stored, eraStart: eraStart
            )
            let records = PRReportBuilder.records(
                exerciseId: exercise.id,
                exerciseName: exercise.name,
                today: entry.sets,
                baseline: baseline,
                lifetime: lifetime
            )
            report.records += records
            if records.isEmpty, let heaviest = PRReportBuilder.heaviest(lifetime) {
                report.lifetimeReferences.append(PRReport.LifetimeReference(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    heaviest: heaviest
                ))
            }
        }
        return report
    }

    /// Completed, weighted sets per exercise, in workout order. An exercise
    /// that appears twice in one workout is one entry.
    private func todaysSets(in workout: Workout) -> [ExerciseSets] {
        var entries: [ExerciseSets] = []
        for workoutExercise in workout.exercises.sorted(by: { $0.order < $1.order }) {
            guard let exercise = workoutExercise.exercise else { continue }
            let sets = workoutExercise.sets.filter(\.isCompleted).compactMap { set -> PRSetRef? in
                guard let kilograms = set.weightInKilograms, kilograms > 0,
                      let reps = set.reps, reps > 0
                else { return nil }
                return PRSetRef(weightKg: kilograms, reps: reps, date: workout.startedAt)
            }
            guard !sets.isEmpty else { continue }
            if let index = entries.firstIndex(where: { sameExercise($0.exercise, exercise) }) {
                entries[index].sets += sets
            } else {
                entries.append(ExerciseSets(exercise: exercise, sets: sets))
            }
        }
        return entries
    }

    private func matches(_ set: PRHistorySet, _ exercise: Exercise) -> Bool {
        if set.exerciseId == exercise.id { return true }
        guard let externalId = exercise.externalId else { return false }
        return set.externalId == externalId
    }

    private func sameExercise(_ lhs: Exercise, _ rhs: Exercise) -> Bool {
        if lhs.id == rhs.id { return true }
        guard let externalId = lhs.externalId else { return false }
        return rhs.externalId == externalId
    }
}
