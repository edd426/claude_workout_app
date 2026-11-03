import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// PR baselines come from history, not only from stored `PersonalRecord`
/// rows (#173), and PRs count from `PREra.start` on, with lifetime bests as
/// reference only (Evan, 2026-11-03).
@Suite("PR baseline from history (#173)")
@MainActor
struct PRBaselineTests {

    /// Keeps the container alive while its context is in use (iOS 26 traps
    /// when a context outlives its container).
    struct Setup {
        let container: ModelContainer
        let context: ModelContext
        let prRepository: SwiftDataPersonalRecordRepository
        let service: PRDetectionService
    }

    func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repository = SwiftDataPersonalRecordRepository(context: context)
        return Setup(
            container: container,
            context: context,
            prRepository: repository,
            service: PRDetectionService(prRepository: repository)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 7)) ?? .now
    }

    /// A finished workout, inserted and saved, as history or as the workout
    /// being finished (production saves it before detecting PRs).
    @discardableResult
    private func insertWorkout(
        _ context: ModelContext,
        exercise: Exercise,
        on day: Date,
        sets: [(weight: Double, unit: WeightUnit, reps: Int)],
        completed: Bool = true
    ) throws -> Workout {
        let workout = Workout(
            name: "Session",
            startedAt: day,
            completedAt: completed ? day.addingTimeInterval(3_000) : nil
        )
        context.insert(workout)
        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(workoutExercise)
        for (index, set) in sets.enumerated() {
            let workoutSet = WorkoutSet(
                order: index,
                weight: set.weight,
                weightUnit: set.unit,
                reps: set.reps,
                isCompleted: true,
                completedAt: day
            )
            context.insert(workoutSet)
            workoutExercise.sets.append(workoutSet)
        }
        workout.exercises.append(workoutExercise)
        try context.save()
        return workout
    }

    private func squat(id: UUID = UUID()) -> Exercise {
        Exercise(id: id, name: "Barbell Squat", isCustom: false, externalId: "Barbell_Squat")
    }

    // MARK: - The four cases from the brief

    @Test("A restored store with history and no PR rows announces no false PR")
    func restoredStoreHasNoFalsePR() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        try insertWorkout(setup.context, exercise: exercise, on: date(2026, 10, 1), sets: [(80, .kg, 8)])
        #expect(try await setup.prRepository.fetchAll().isEmpty)

        let today = try insertWorkout(setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(65, .kg, 8)])
        let records = try await setup.service.detectPRs(for: today)

        #expect(records.isEmpty)
    }

    @Test("History matches by externalId when the exercise UUIDs differ")
    func matchesByExternalIdAcrossUUIDs() async throws {
        let setup = try makeSetup()
        let before = squat()
        let reimported = squat()
        #expect(before.id != reimported.id)
        setup.context.insert(before)
        setup.context.insert(reimported)
        try insertWorkout(setup.context, exercise: before, on: date(2026, 10, 1), sets: [(80, .kg, 8)])

        let lighter = try insertWorkout(
            setup.context, exercise: reimported, on: date(2026, 11, 2), sets: [(65, .kg, 8)], completed: false
        )
        #expect(try await setup.service.detectPRs(for: lighter).isEmpty)

        let heavier = try insertWorkout(
            setup.context, exercise: reimported, on: date(2026, 11, 3), sets: [(85, .kg, 8)], completed: false
        )
        let records = try await setup.service.detectPRs(for: heavier)
        #expect(records.contains { $0.prType == .heaviestWeight && $0.value == 85 })
    }

    @Test("A pre-2026 heavier set doesn't block a 2026 PR, and shows as the lifetime best")
    func preEraSetIsLifetimeReferenceOnly() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        try insertWorkout(setup.context, exercise: exercise, on: date(2019, 6, 1), sets: [(100, .kg, 5)])
        try insertWorkout(setup.context, exercise: exercise, on: date(2026, 3, 1), sets: [(60, .kg, 5)])

        let today = try insertWorkout(setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(70, .kg, 5)])
        let report = try #require(try await setup.service.prReport(for: today))

        let heaviest = try #require(report.records.first { $0.type == .heaviestWeight })
        #expect(heaviest.value == 70)
        #expect(heaviest.exerciseName == "Barbell Squat")
        let lifetime = try #require(heaviest.lifetimeBest)
        #expect(lifetime.weightKg == 100)
        #expect(lifetime.reps == 5)
        #expect(Calendar.current.component(.year, from: lifetime.date) == 2019)
        #expect(!heaviest.isNewLifetimeBest)
    }

    @Test("Mixed lbs and kg history compares in kilograms")
    func mixedUnitsCompareInKilograms() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        // 200 lb = 90.72 kg
        try insertWorkout(setup.context, exercise: exercise, on: date(2026, 5, 1), sets: [(200, .lbs, 5)])

        let today = try insertWorkout(
            setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(90, .kg, 5)], completed: false
        )
        #expect(try await setup.service.detectPRs(for: today).isEmpty)
    }

    @Test("A pounds set beats a lighter kilogram history, valued in kilograms")
    func poundsSetBeatsLighterKilograms() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        try insertWorkout(setup.context, exercise: exercise, on: date(2026, 5, 1), sets: [(90, .kg, 5)])

        let today = try insertWorkout(setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(200, .lbs, 5)])
        let records = try await setup.service.detectPRs(for: today)

        let heaviest = try #require(records.first { $0.prType == .heaviestWeight })
        #expect(abs(heaviest.value - 90.718) < 0.01)
    }

    // MARK: - Semantics

    @Test("A reps PR needs more reps than any 2026 set at that weight or heavier")
    func repsPRIsDominanceBased() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        try insertWorkout(setup.context, exercise: exercise, on: date(2026, 10, 1), sets: [(80, .kg, 8)])

        let today = try insertWorkout(
            setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(80, .kg, 10), (70, .kg, 8)]
        )
        let records = try await setup.service.detectPRs(for: today)

        let reps = records.filter { $0.prType == .mostRepsAtWeight }
        #expect(reps.count == 1)
        #expect(reps.first?.weight == 80)
        #expect(reps.first?.reps == 10)
    }

    @Test("An unfinished workout is not history")
    func unfinishedWorkoutIsNotBaseline() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        try insertWorkout(setup.context, exercise: exercise, on: date(2026, 10, 1), sets: [(120, .kg, 5)], completed: false)

        let today = try insertWorkout(setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(80, .kg, 5)])
        let records = try await setup.service.detectPRs(for: today)

        #expect(records.contains { $0.prType == .heaviestWeight && $0.value == 80 })
    }

    @Test("The report ignores the workout's own saved records, so it can be read after detection")
    func reportAfterDetectionMatchesDetection() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        try insertWorkout(setup.context, exercise: exercise, on: date(2026, 10, 1), sets: [(80, .kg, 5)])
        let today = try insertWorkout(setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(90, .kg, 5)])

        let detected = try await setup.service.detectPRs(for: today)
        let fresh = PRDetectionService(prRepository: setup.prRepository)
        let report = try #require(try await fresh.prReport(for: today))

        #expect(!detected.isEmpty)
        #expect(Set(report.records.map(\.type)) == Set(detected.map(\.prType)))
    }

    @Test("A heavier set beating every earlier set is a new lifetime best")
    func newLifetimeBest() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        try insertWorkout(setup.context, exercise: exercise, on: date(2019, 6, 1), sets: [(100, .kg, 5)])
        let today = try insertWorkout(setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(102.5, .kg, 5)])

        let report = try #require(try await setup.service.prReport(for: today))
        let heaviest = try #require(report.records.first { $0.type == .heaviestWeight })

        #expect(heaviest.isNewLifetimeBest)
    }

    @Test("Exercises done today with no 2026 PR list their lifetime best")
    func lifetimeReferencesForExercisesWithoutPR() async throws {
        let setup = try makeSetup()
        let exercise = squat()
        setup.context.insert(exercise)
        try insertWorkout(setup.context, exercise: exercise, on: date(2019, 6, 1), sets: [(100, .kg, 5)])
        try insertWorkout(setup.context, exercise: exercise, on: date(2026, 10, 1), sets: [(80, .kg, 5)])
        let today = try insertWorkout(setup.context, exercise: exercise, on: date(2026, 11, 2), sets: [(75, .kg, 5)])

        let report = try #require(try await setup.service.prReport(for: today))

        #expect(report.records.isEmpty)
        let reference = try #require(report.lifetimeReferences.first)
        #expect(reference.exerciseName == "Barbell Squat")
        #expect(reference.heaviest.weightKg == 100)
    }

    @Test("PRs count from 1 January 2026")
    func eraStartsIn2026() {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: PREra.start)
        #expect(components.year == 2026)
        #expect(components.month == 1)
        #expect(components.day == 1)
        #expect(components.hour == 0)
        #expect(PREra.label == "since 2026")
    }

    // MARK: - Display

    @Test("Weights display in the preferred unit", arguments: [
        (100.0, WeightUnit.kg, "100 kg"),
        (102.5, WeightUnit.kg, "102.5 kg"),
        (100.0, WeightUnit.lbs, "220.5 lbs"),
        (45.359237, WeightUnit.lbs, "100 lbs"),
    ])
    func weightDisplay(kilograms: Double, unit: WeightUnit, expected: String) {
        #expect(PRDisplay.weight(kilograms, in: unit) == expected)
    }

    @Test("A lifetime best before this year shows its year")
    func lifetimeLineShowsYear() {
        let set = PRSetRef(weightKg: 100, reps: 5, date: date(2019, 6, 1))
        let line = PRDisplay.lifetimeBest(set, in: .kg, now: date(2026, 11, 3))
        #expect(line == "lifetime best 100 kg × 5 · 2019")
    }

    @Test("A record line reads in the preferred unit")
    func recordValueInPounds() {
        let set = PRSetRef(weightKg: 100, reps: 5, date: date(2026, 11, 2))
        #expect(PRDisplay.setText(set, in: .lbs) == "220.5 lbs × 5")
    }
}
