import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("WorkoutRepository Tests")
struct WorkoutRepositoryTests {
    @Test("fetchAll returns empty when no workouts")
    @MainActor
    func fetchAllEmpty() async throws {
        let container = try makeTestContainer()
        let repo = SwiftDataWorkoutRepository(context: container.mainContext)
        let results = try await repo.fetchAll()
        #expect(results.isEmpty)
    }

    @Test("fetchAll returns workouts sorted by startedAt descending")
    @MainActor
    func fetchAllSorted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let older = Workout(name: "Older", startedAt: Date(timeIntervalSinceNow: -7200))
        let newer = Workout(name: "Newer", startedAt: Date(timeIntervalSinceNow: -3600))
        context.insert(older)
        context.insert(newer)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let results = try await repo.fetchAll()
        #expect(results.count == 2)
        #expect(results[0].name == "Newer")
        #expect(results[1].name == "Older")
    }

    @Test("fetch by id returns correct workout")
    @MainActor
    func fetchById() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workout = Workout(name: "Push Day", startedAt: .now)
        context.insert(workout)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let found = try await repo.fetch(id: workout.id)
        #expect(found?.name == "Push Day")
    }

    @Test("fetchByTemplate returns workouts started from template")
    @MainActor
    func fetchByTemplate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let templateId = UUID()
        let w1 = Workout(name: "Push A", startedAt: .now, templateId: templateId)
        let w2 = Workout(name: "Push B", startedAt: .now, templateId: templateId)
        let w3 = Workout(name: "Pull", startedAt: .now, templateId: UUID())
        context.insert(w1)
        context.insert(w2)
        context.insert(w3)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let results = try await repo.fetchByTemplate(id: templateId)
        #expect(results.count == 2)
    }

    @Test("recentSets returns last completed sets for an exercise")
    @MainActor
    func recentSets() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let workout = Workout(name: "Push Day", startedAt: Date(timeIntervalSinceNow: -3600), completedAt: Date())
        context.insert(workout)

        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        workout.exercises.append(we)

        let set1 = WorkoutSet(order: 0, weight: 60.0, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: Date())
        let set2 = WorkoutSet(order: 1, weight: 65.0, weightUnit: .kg, reps: 6, isCompleted: true, completedAt: Date())
        context.insert(set1)
        context.insert(set2)
        we.sets.append(set1)
        we.sets.append(set2)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let sets = try await repo.recentSets(for: exercise.id, limit: 10)
        #expect(sets.count == 2)
    }

    @Test("recentSets respects limit")
    @MainActor
    func recentSetsLimit() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Squat")
        context.insert(exercise)

        // Create two workouts each with 3 sets
        for i in 0..<2 {
            let workout = Workout(
                name: "Leg Day \(i)",
                startedAt: Date(timeIntervalSinceNow: Double(-3600 * (i + 1))),
                completedAt: Date()
            )
            context.insert(workout)
            let we = WorkoutExercise(order: 0, exercise: exercise)
            context.insert(we)
            workout.exercises.append(we)
            for j in 0..<3 {
                let s = WorkoutSet(order: j, weight: 100.0, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: Date())
                context.insert(s)
                we.sets.append(s)
            }
        }
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let sets = try await repo.recentSets(for: exercise.id, limit: 3)
        #expect(sets.count == 3)
    }

    @Test("lastWorkoutDate returns date of most recent workout containing exercise")
    @MainActor
    func lastWorkoutDate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Deadlift")
        context.insert(exercise)

        let older = Workout(name: "Older", startedAt: Date(timeIntervalSinceNow: -7200), completedAt: Date(timeIntervalSinceNow: -6000))
        let newer = Workout(name: "Newer", startedAt: Date(timeIntervalSinceNow: -3600), completedAt: Date(timeIntervalSinceNow: -2000))
        context.insert(older)
        context.insert(newer)

        for workout in [older, newer] {
            let we = WorkoutExercise(order: 0, exercise: exercise)
            context.insert(we)
            workout.exercises.append(we)
            let s = WorkoutSet(order: 0, weight: 100.0, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: Date())
            context.insert(s)
            we.sets.append(s)
        }
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let date = try await repo.lastWorkoutDate(for: exercise.id)
        #expect(date != nil)
        #expect(abs(date!.timeIntervalSince(newer.startedAt)) < 1.0)
    }

    @Test("lastWorkoutDate returns nil when exercise has never been performed")
    @MainActor
    func lastWorkoutDateNeverPerformed() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Unused Exercise")
        context.insert(exercise)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let date = try await repo.lastWorkoutDate(for: exercise.id)
        #expect(date == nil)
    }

    @Test("save persists a new workout")
    @MainActor
    func saveWorkout() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataWorkoutRepository(context: context)
        let workout = Workout(name: "Leg Day", startedAt: .now)
        try await repo.save(workout)

        let results = try await repo.fetchAll()
        #expect(results.count == 1)
    }

    @Test("delete removes workout")
    @MainActor
    func deleteWorkout() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workout = Workout(name: "Pull Day", startedAt: .now)
        context.insert(workout)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        try await repo.delete(workout)

        let results = try await repo.fetchAll()
        #expect(results.isEmpty)
    }
}
