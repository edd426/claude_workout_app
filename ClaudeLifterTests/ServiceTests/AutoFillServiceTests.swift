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
