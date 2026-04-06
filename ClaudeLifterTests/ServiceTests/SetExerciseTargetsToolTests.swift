import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("SetExerciseTargetsTool Tests")
@MainActor
struct SetExerciseTargetsToolTests {

    private func makeWorkoutWithExercise(
        exerciseName: String = "Bench Press",
        sets: [(weight: Double?, reps: Int?)] = [(80.0, 8), (80.0, 8), (80.0, 8)]
    ) -> (Workout, Exercise) {
        let exercise = TestFixtures.makeExercise(name: exerciseName)
        let workout = Workout(name: "Push Day", startedAt: .now)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        for (i, s) in sets.enumerated() {
            let ws = WorkoutSet(order: i, weight: s.weight, weightUnit: .kg, reps: s.reps)
            we.sets.append(ws)
        }
        workout.exercises = [we]
        return (workout, exercise)
    }

    private func makeContext(workout: Workout?) -> ToolContext {
        ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )
    }

    // MARK: - Reps

    @Test("Updates reps on all sets")
    func updatesRepsOnAllSets() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let context = makeContext(workout: workout)
        let tool = SetExerciseTargetsTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "reps": 12}"#,
            context: context
        )

        let we = workout.exercises[0]
        #expect(we.sets.count == 3)
        for s in we.sets {
            #expect(s.reps == 12)
        }
        #expect(result.contains("Bench Press"))
    }

    // MARK: - Add sets

    @Test("Adds sets when count increases")
    func addsSetsWhenCountIncreases() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let context = makeContext(workout: workout)
        let tool = SetExerciseTargetsTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "sets": 5}"#,
            context: context
        )

        let we = workout.exercises[0]
        #expect(we.sets.count == 5)
        // New sets should carry forward weight/reps from existing sets
        let sorted = we.sets.sorted { $0.order < $1.order }
        #expect(sorted[3].weight == 80.0)
        #expect(sorted[3].reps == 8)
        #expect(sorted[4].weight == 80.0)
        #expect(sorted[4].reps == 8)
        #expect(result.contains("5"))
    }

    // MARK: - Remove sets

    @Test("Removes sets when count decreases, from end")
    func removesSetsWhenCountDecreases() async throws {
        let (workout, _) = makeWorkoutWithExercise(sets: [
            (80.0, 8), (80.0, 8), (80.0, 8), (80.0, 8)
        ])
        let context = makeContext(workout: workout)
        let tool = SetExerciseTargetsTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "sets": 2}"#,
            context: context
        )

        let we = workout.exercises[0]
        #expect(we.sets.count == 2)
        #expect(result.contains("2"))
    }

    // MARK: - Weight and unit

    @Test("Updates weight and unit on all sets")
    func updatesWeightAndUnit() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let context = makeContext(workout: workout)
        let tool = SetExerciseTargetsTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "weight": 100.0, "weight_unit": "lbs"}"#,
            context: context
        )

        let we = workout.exercises[0]
        for s in we.sets {
            #expect(s.weight == 100.0)
            #expect(s.weightUnit == .lbs)
        }
        #expect(result.contains("100.0"))
        #expect(result.contains("lbs"))
    }

    // MARK: - Error cases

    @Test("Returns error when no active workout")
    func noActiveWorkout() async throws {
        let context = makeContext(workout: nil)
        let tool = SetExerciseTargetsTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "reps": 10}"#,
            context: context
        )

        #expect(result.contains("No active workout"))
    }

    @Test("Returns error when exercise not found in workout")
    func exerciseNotFound() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let context = makeContext(workout: workout)
        let tool = SetExerciseTargetsTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Squat", "reps": 5}"#,
            context: context
        )

        #expect(result.contains("not found"))
    }

    // MARK: - Save

    @Test("Saves workout after mutation")
    func savesWorkout() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let workoutRepo = MockWorkoutRepository()
        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: workoutRepo,
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )
        let tool = SetExerciseTargetsTool()

        _ = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "reps": 10}"#,
            context: context
        )

        #expect(workoutRepo.saveCallCount == 1)
    }
}
