import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("PRDetectionService Tests")
@MainActor
struct PRDetectionServiceTests {

    // MARK: - Helpers

    /// Holds the container alongside the context: returning only the context
    /// deallocated the container at helper return, and the iOS 26.5 SwiftData
    /// runtime traps on any use of a context whose container is gone (the
    /// 26.2 runtime silently tolerated it — all 8 persistence tests here
    /// crashed with SIGTRAP after the toolchain update).
    struct Setup {
        let container: ModelContainer
        let context: ModelContext
        let service: PRDetectionService
    }

    func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        let context = container.mainContext
        let prRepo = SwiftDataPersonalRecordRepository(context: context)
        let service = PRDetectionService(prRepository: prRepo)
        return Setup(container: container, context: context, service: service)
    }

    func insertWorkout(context: ModelContext, exercise: Exercise, sets: [(weight: Double, reps: Int)]) -> Workout {
        let workout = TestFixtures.makeWorkout()
        context.insert(workout)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        for (i, s) in sets.enumerated() {
            let ws = WorkoutSet(order: i, weight: s.weight, weightUnit: .kg, reps: s.reps, isCompleted: true, completedAt: .now)
            context.insert(ws)
            we.sets.append(ws)
        }
        workout.exercises.append(we)
        return workout
    }

    // MARK: - Tests

    @Test("Detects heaviest weight PR")
    func detectsHeaviestWeightPR() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let workout = insertWorkout(context: context, exercise: exercise, sets: [(100.0, 5)])
        let newPRs = try await service.detectPRs(for: workout)

        let weightPR = newPRs.first { $0.prType == .heaviestWeight }
        #expect(weightPR != nil)
        #expect(weightPR?.value == 100.0)
    }

    @Test("Detects most reps at weight PR")
    func detectsMostRepsAtWeightPR() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let workout = insertWorkout(context: context, exercise: exercise, sets: [(60.0, 15)])
        let newPRs = try await service.detectPRs(for: workout)

        let repsPR = newPRs.first { $0.prType == .mostRepsAtWeight }
        #expect(repsPR != nil)
        #expect(repsPR?.reps == 15)
        #expect(repsPR?.weight == 60.0)
    }

    @Test("Detects highest estimated 1RM PR")
    func detectsHighest1RMPR() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let workout = insertWorkout(context: context, exercise: exercise, sets: [(100.0, 5)])
        let newPRs = try await service.detectPRs(for: workout)

        let oneRepMaxPR = newPRs.first { $0.prType == .highest1RM }
        #expect(oneRepMaxPR != nil)
        // 100 * (36 / (37-5)) = 112.5
        #expect(abs((oneRepMaxPR?.value ?? 0) - 112.5) < 0.01)
    }

    @Test("Does not create PR if existing record is higher")
    func doesNotCreatePRIfExistingIsHigher() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        let workoutId = UUID()

        // Insert existing PR of 120kg
        let existingPR = PersonalRecord(exerciseId: exercise.id, type: .heaviestWeight, value: 120.0, weight: 120.0, workoutId: workoutId)
        context.insert(existingPR)
        try context.save()

        // New workout with 100kg — below existing PR
        let workout = insertWorkout(context: context, exercise: exercise, sets: [(100.0, 5)])
        let newPRs = try await service.detectPRs(for: workout)

        let weightPR = newPRs.first { $0.prType == .heaviestWeight }
        #expect(weightPR == nil)
    }

    @Test("A 100 lb set does not beat a 60 kg PR")
    func poundsDoNotPoisonKilogramPRComparisons() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let historicalWorkout = insertWorkout(
            context: context,
            exercise: exercise,
            sets: [(60.0, 5)]
        )
        _ = try await service.detectPRs(for: historicalWorkout)

        let currentWorkout = TestFixtures.makeWorkout()
        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        workoutExercise.sets.append(
            WorkoutSet(
                order: 0,
                weight: 100,
                weightUnit: .lbs,
                reps: 5,
                isCompleted: true,
                completedAt: .now
            )
        )
        currentWorkout.exercises.append(workoutExercise)

        let newPRs = try await service.detectPRs(for: currentWorkout)

        #expect(!newPRs.contains { $0.prType == .heaviestWeight })
        #expect(!newPRs.contains { $0.prType == .highest1RM })
        let repsAtWeight = try #require(
            newPRs.first { $0.prType == .mostRepsAtWeight }
        )
        #expect(abs((repsAtWeight.weight ?? 0) - 45.3592) < 0.001)
    }

    @Test("Brzycki formula calculates correctly for 5 reps")
    func brzykiFormulaFiveReps() {
        // 100kg x 5 reps = 100 * (36 / 32) = 112.5
        let set = WorkoutSet(order: 0, weight: 100, weightUnit: .kg, reps: 5)
        let result = PersonalRecord.estimated1RM(for: set)
        #expect(result != nil)
        #expect(abs(result! - 112.5) < 0.01)
    }

    @Test("Brzycki formula returns nil for reps greater than 36")
    func brzykiFormulaEdgeCase() {
        let set = WorkoutSet(order: 0, weight: 100, weightUnit: .kg, reps: 37)
        let result = PersonalRecord.estimated1RM(for: set)
        #expect(result == nil)
    }

    @Test("Multiple PRs detected in single workout for different exercises")
    func multiplePRsForDifferentExercises() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let squat = TestFixtures.makeSquat()
        context.insert(bench)
        context.insert(squat)

        let workout = TestFixtures.makeWorkout()
        context.insert(workout)

        let we1 = WorkoutExercise(order: 0, exercise: bench)
        context.insert(we1)
        let s1 = WorkoutSet(order: 0, weight: 100.0, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: .now)
        context.insert(s1)
        we1.sets.append(s1)
        workout.exercises.append(we1)

        let we2 = WorkoutExercise(order: 1, exercise: squat)
        context.insert(we2)
        let s2 = WorkoutSet(order: 0, weight: 140.0, weightUnit: .kg, reps: 3, isCompleted: true, completedAt: .now)
        context.insert(s2)
        we2.sets.append(s2)
        workout.exercises.append(we2)

        let newPRs = try await service.detectPRs(for: workout)

        let benchPRs = newPRs.filter { $0.exerciseId == bench.id }
        let squatPRs = newPRs.filter { $0.exerciseId == squat.id }
        #expect(benchPRs.count > 0)
        #expect(squatPRs.count > 0)
    }

    @Test("First-ever exercise: all completed sets create PRs")
    func firstEverExerciseAllSetsArePRs() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let exercise = TestFixtures.makeExercise(name: "Overhead Press")
        context.insert(exercise)

        // No prior PRs exist for this exercise
        let workout = insertWorkout(context: context, exercise: exercise, sets: [(50.0, 10)])
        let newPRs = try await service.detectPRs(for: workout)

        // Should get heaviestWeight, mostRepsAtWeight, highest1RM
        let types = Set(newPRs.map { $0.prType })
        #expect(types.contains(.heaviestWeight))
        #expect(types.contains(.mostRepsAtWeight))
        #expect(types.contains(.highest1RM))
    }

    @Test("Returns empty array for workout with no completed sets")
    func emptyArrayForNoCompletedSets() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let workout = TestFixtures.makeWorkout()
        context.insert(workout)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        // Add an incomplete set
        let ws = WorkoutSet(order: 0, weight: 100.0, weightUnit: .kg, reps: 5, isCompleted: false)
        context.insert(ws)
        we.sets.append(ws)
        workout.exercises.append(we)

        let newPRs = try await service.detectPRs(for: workout)
        #expect(newPRs.isEmpty)
    }

    @Test("PR detection is per-exercise, not global")
    func prDetectionIsPerExercise() async throws {
        let setup = try makeSetup()
        let (context, service) = (setup.context, setup.service)
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let squat = TestFixtures.makeSquat()
        context.insert(bench)
        context.insert(squat)
        let workoutId = UUID()

        // Bench already has a 120kg PR
        let existingPR = PersonalRecord(exerciseId: bench.id, type: .heaviestWeight, value: 120.0, weight: 120.0, workoutId: workoutId)
        context.insert(existingPR)
        try context.save()

        // New workout: bench at 100kg (below PR), squat at 140kg (no prior PR)
        let workout = TestFixtures.makeWorkout()
        context.insert(workout)

        let we1 = WorkoutExercise(order: 0, exercise: bench)
        context.insert(we1)
        let s1 = WorkoutSet(order: 0, weight: 100.0, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: .now)
        context.insert(s1)
        we1.sets.append(s1)
        workout.exercises.append(we1)

        let we2 = WorkoutExercise(order: 1, exercise: squat)
        context.insert(we2)
        let s2 = WorkoutSet(order: 0, weight: 140.0, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: .now)
        context.insert(s2)
        we2.sets.append(s2)
        workout.exercises.append(we2)

        let newPRs = try await service.detectPRs(for: workout)

        // Bench should have no heaviest weight PR (100 < 120)
        let benchWeightPR = newPRs.first { $0.exerciseId == bench.id && $0.prType == .heaviestWeight }
        #expect(benchWeightPR == nil)

        // Squat should have a new heaviest weight PR
        let squatWeightPR = newPRs.first { $0.exerciseId == squat.id && $0.prType == .heaviestWeight }
        #expect(squatWeightPR != nil)
        #expect(squatWeightPR?.value == 140.0)
    }
}
