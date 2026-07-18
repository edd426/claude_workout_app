import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("AutoFillService Tests")
struct AutoFillServiceTests {
    @Test("returns nil when no prior sets for exercise")
    @MainActor
    func noPriorSets() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataWorkoutRepository(context: context)
        let service = AutoFillService(workoutRepository: repo)

        let result = try await service.lastPerformed(exerciseId: UUID())
        #expect(result == nil)
    }

    @Test("returns last completed set weight and reps")
    @MainActor
    func returnsLastSet() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let workout = Workout(name: "Push Day", startedAt: Date(timeIntervalSinceNow: -3600), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        workout.exercises.append(we)

        let set1 = WorkoutSet(order: 0, weight: 60.0, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: Date(timeIntervalSinceNow: -100))
        let set2 = WorkoutSet(order: 1, weight: 65.0, weightUnit: .kg, reps: 6, isCompleted: true, completedAt: Date(timeIntervalSinceNow: -50))
        context.insert(set1)
        context.insert(set2)
        we.sets.append(set1)
        we.sets.append(set2)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let service = AutoFillService(workoutRepository: repo)

        let result = try await service.lastPerformed(exerciseId: exercise.id)
        #expect(result != nil)
        // Returns the last set (highest order) from the most recent workout
        #expect(result?.weight == 65.0)
        #expect(result?.reps == 6)
        #expect(result?.weightUnit == .kg)
    }

    @Test("returns most recent workout's last set, not older ones")
    @MainActor
    func returnsMostRecentWorkout() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Squat")
        context.insert(exercise)

        // Older workout
        let oldWorkout = Workout(name: "Old Leg Day", startedAt: Date(timeIntervalSinceNow: -7200), completedAt: Date(timeIntervalSinceNow: -5000))
        context.insert(oldWorkout)
        let oldWE = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(oldWE)
        oldWorkout.exercises.append(oldWE)
        let oldSet = WorkoutSet(order: 0, weight: 80.0, weightUnit: .kg, reps: 10, isCompleted: true, completedAt: Date())
        context.insert(oldSet)
        oldWE.sets.append(oldSet)

        // Newer workout
        let newWorkout = Workout(name: "New Leg Day", startedAt: Date(timeIntervalSinceNow: -3600), completedAt: Date(timeIntervalSinceNow: -1000))
        context.insert(newWorkout)
        let newWE = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(newWE)
        newWorkout.exercises.append(newWE)
        let newSet = WorkoutSet(order: 0, weight: 100.0, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: Date())
        context.insert(newSet)
        newWE.sets.append(newSet)

        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let service = AutoFillService(workoutRepository: repo)

        let result = try await service.lastPerformed(exerciseId: exercise.id)
        #expect(result?.weight == 100.0)
        #expect(result?.reps == 5)
    }

    @Test("ignores incomplete sets")
    @MainActor
    func ignoresIncompleteSets() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Deadlift")
        context.insert(exercise)

        let workout = Workout(name: "Pull Day", startedAt: Date(timeIntervalSinceNow: -3600), completedAt: Date())
        context.insert(workout)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        workout.exercises.append(we)

        let completedSet = WorkoutSet(order: 0, weight: 120.0, weightUnit: .kg, reps: 3, isCompleted: true, completedAt: Date())
        let incompleteSet = WorkoutSet(order: 1, weight: 130.0, weightUnit: .kg, reps: nil, isCompleted: false, completedAt: nil)
        context.insert(completedSet)
        context.insert(incompleteSet)
        we.sets.append(completedSet)
        we.sets.append(incompleteSet)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let service = AutoFillService(workoutRepository: repo)

        let result = try await service.lastPerformed(exerciseId: exercise.id)
        #expect(result?.weight == 120.0)
        #expect(result?.reps == 3)
    }

    @Test("AutoFillResult captures correct date")
    @MainActor
    func capturesDate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Pull-up")
        context.insert(exercise)

        let completedAt = Date(timeIntervalSinceNow: -500)
        let workout = Workout(name: "Back Day", startedAt: Date(timeIntervalSinceNow: -3600), completedAt: Date())
        context.insert(workout)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        workout.exercises.append(we)
        let set = WorkoutSet(order: 0, weight: nil, weightUnit: .kg, reps: 12, isCompleted: true, completedAt: completedAt)
        context.insert(set)
        we.sets.append(set)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let service = AutoFillService(workoutRepository: repo)

        let result = try await service.lastPerformed(exerciseId: exercise.id)
        #expect(result?.reps == 12)
        #expect(result?.weight == nil)
        #expect(abs(result!.date.timeIntervalSince(completedAt)) < 1.0)
    }
}

/// Issue #82 — auto-fill must map per set index from the previous session
/// (set 1 → set 1, set 2 → set 2, …) instead of replicating the previous
/// session's final set across every set, which flattened warm-up → top-set
/// structure.
@Suite("AutoFillService per-set index mapping (#82)")
struct AutoFillPerSetMappingTests {

    /// Seeds one completed previous session for a fresh exercise. Set `i` gets
    /// `weights[i]`, reps `10 + i`, unit `units[i]` (default .kg), and a
    /// distinct completedAt spaced 60s apart. `completedFlags[i]` (default
    /// true) controls isCompleted; incomplete sets get nil completedAt.
    @MainActor
    private func seedPreviousSession(
        context: ModelContext,
        weights: [Double?],
        units: [WeightUnit]? = nil,
        completedFlags: [Bool]? = nil,
        startedAt: Date = Date(timeIntervalSinceNow: -3600)
    ) throws -> Exercise {
        let exercise = TestFixtures.makeExercise(name: "Mapped Exercise \(UUID().uuidString)")
        context.insert(exercise)
        try seedSession(
            context: context,
            exercise: exercise,
            weights: weights,
            units: units,
            completedFlags: completedFlags,
            startedAt: startedAt
        )
        return exercise
    }

    /// Seeds an additional session for an existing exercise.
    @MainActor
    private func seedSession(
        context: ModelContext,
        exercise: Exercise,
        weights: [Double?],
        units: [WeightUnit]? = nil,
        completedFlags: [Bool]? = nil,
        startedAt: Date
    ) throws {
        let workout = Workout(
            name: "Previous Session",
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(1800)
        )
        context.insert(workout)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        workout.exercises.append(we)
        for (i, weight) in weights.enumerated() {
            let isCompleted = completedFlags?[i] ?? true
            let set = WorkoutSet(
                order: i,
                weight: weight,
                weightUnit: units?[i] ?? .kg,
                reps: 10 + i,
                isCompleted: isCompleted,
                completedAt: isCompleted ? startedAt.addingTimeInterval(Double(300 + i * 60)) : nil
            )
            context.insert(set)
            we.sets.append(set)
        }
        try context.save()
    }

    @Test("maps weights per set index, with sensible fallback when counts differ", arguments: [
        // equal counts: straight per-index mapping
        ([60.0, 80.0, 100.0], 3, [60.0, 80.0, 100.0]),
        // new session has MORE sets: repeat previous last set for extras
        ([60.0, 100.0], 4, [60.0, 100.0, 100.0, 100.0]),
        // new session has FEWER sets: extra previous sets are ignored
        ([10.0, 20.0, 30.0, 40.0, 50.0], 3, [10.0, 20.0, 30.0]),
        // single-set new session maps to the FIRST previous set, not the last
        ([60.0, 80.0, 100.0], 1, [60.0]),
        // single previous set repeats across all new sets
        ([42.5], 3, [42.5, 42.5, 42.5]),
    ])
    @MainActor
    func perIndexWeightMapping(
        previousWeights: [Double],
        setCount: Int,
        expectedWeights: [Double]
    ) async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = try seedPreviousSession(context: context, weights: previousWeights)
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: exercise.id, setCount: setCount)

        #expect(results.count == setCount)
        #expect(results.map(\.weight) == expectedWeights.map(Optional.init))
    }

    @Test("preserves warm-up to top-set structure: reps and dates map per index")
    @MainActor
    func repsAndDatesMapPerIndex() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        // Warm-up 60x10, back-off 80x11, top set 100x12 (reps are 10 + i)
        let exercise = try seedPreviousSession(context: context, weights: [60.0, 80.0, 100.0])
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: exercise.id, setCount: 3)

        #expect(results.map(\.reps) == [10, 11, 12])
        // Each result's date is the matching previous set's completedAt (60s apart)
        try #require(results.count == 3)
        #expect(results[1].date.timeIntervalSince(results[0].date) == 60)
        #expect(results[2].date.timeIntervalSince(results[1].date) == 60)
    }

    @Test("carries weight unit per set, extras inherit the last previous set's unit")
    @MainActor
    func carriesWeightUnitPerSet() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = try seedPreviousSession(
            context: context,
            weights: [60.0, 135.0],
            units: [.kg, .lbs]
        )
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: exercise.id, setCount: 3)

        #expect(results.map(\.weightUnit) == [.kg, .lbs, .lbs])
    }

    @Test("carries nil weight (bodyweight set) per index")
    @MainActor
    func carriesNilWeightPerIndex() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = try seedPreviousSession(context: context, weights: [nil, 20.0])
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: exercise.id, setCount: 2)

        #expect(results.map(\.weight) == [nil, 20.0])
    }

    @Test("maps against completed sets only, compacting over incomplete ones")
    @MainActor
    func skipsIncompleteSetsWhenMapping() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        // Middle set was never completed — mapping compacts to [60, 100]
        let exercise = try seedPreviousSession(
            context: context,
            weights: [60.0, 130.0, 100.0],
            completedFlags: [true, false, true]
        )
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: exercise.id, setCount: 3)

        #expect(results.map(\.weight) == [60.0, 100.0, 100.0])
    }

    @Test("falls back to an older session when the newest has no completed sets")
    @MainActor
    func fallsBackToOlderSession() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        // Older session: completed 70x10, 90x11
        let exercise = try seedPreviousSession(
            context: context,
            weights: [70.0, 90.0],
            startedAt: Date(timeIntervalSinceNow: -7200)
        )
        // Newest session: nothing completed
        try seedSession(
            context: context,
            exercise: exercise,
            weights: [200.0, 210.0],
            completedFlags: [false, false],
            startedAt: Date(timeIntervalSinceNow: -3600)
        )
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: exercise.id, setCount: 2)

        #expect(results.map(\.weight) == [70.0, 90.0])
    }

    @Test("returns empty when there is no previous session")
    @MainActor
    func emptyWhenNoPreviousSession() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: UUID(), setCount: 3)

        #expect(results.isEmpty)
    }

    @Test("returns empty when the only previous session has no completed sets")
    @MainActor
    func emptyWhenNoCompletedSets() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = try seedPreviousSession(
            context: context,
            weights: [60.0, 80.0],
            completedFlags: [false, false]
        )
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: exercise.id, setCount: 2)

        #expect(results.isEmpty)
    }

    @Test("returns empty for a non-positive set count even with history")
    @MainActor
    func emptyForNonPositiveSetCount() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = try seedPreviousSession(context: context, weights: [60.0, 80.0])
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let results = try await service.autoFillValues(exerciseId: exercise.id, setCount: 0)

        #expect(results.isEmpty)
    }

    @Test("legacy lastPerformed still returns the final set of the previous session")
    @MainActor
    func lastPerformedStillReturnsFinalSet() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = try seedPreviousSession(context: context, weights: [60.0, 80.0, 100.0])
        let service = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: context))

        let result = try await service.lastPerformed(exerciseId: exercise.id)

        #expect(result?.weight == 100.0)
        #expect(result?.reps == 12)
    }
}
