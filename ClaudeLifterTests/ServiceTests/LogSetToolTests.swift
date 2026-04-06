import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("LogSetTool Tests")
@MainActor
struct LogSetToolTests {

    private func makeWorkoutWithExercise(
        exerciseName: String = "Bench Press",
        sets: [(weight: Double?, reps: Int?, completed: Bool)] = [
            (80.0, 8, false), (80.0, 8, false), (80.0, 8, false)
        ]
    ) -> (Workout, Exercise) {
        let exercise = TestFixtures.makeExercise(name: exerciseName)
        let workout = Workout(name: "Push Day", startedAt: .now)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        for (i, s) in sets.enumerated() {
            let ws = WorkoutSet(
                order: i,
                weight: s.weight,
                weightUnit: .kg,
                reps: s.reps,
                isCompleted: s.completed,
                completedAt: s.completed ? .now : nil
            )
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

    // MARK: - Next incomplete set

    @Test("Completes next incomplete set when no set_number provided")
    func completesNextIncompleteSet() async throws {
        let (workout, _) = makeWorkoutWithExercise(sets: [
            (80.0, 8, true), (80.0, 8, false), (80.0, 8, false)
        ])
        let context = makeContext(workout: workout)
        let tool = LogSetTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press"}"#,
            context: context
        )

        let sorted = workout.exercises[0].sets.sorted { $0.order < $1.order }
        #expect(sorted[1].isCompleted == true)
        #expect(sorted[1].completedAt != nil)
        #expect(sorted[2].isCompleted == false)
        #expect(result.contains("set 2"))
    }

    // MARK: - Specific set number

    @Test("Completes specific set by set_number (1-indexed)")
    func completesSpecificSet() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let context = makeContext(workout: workout)
        let tool = LogSetTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "set_number": 3}"#,
            context: context
        )

        let sorted = workout.exercises[0].sets.sorted { $0.order < $1.order }
        #expect(sorted[2].isCompleted == true)
        #expect(sorted[2].completedAt != nil)
        #expect(result.contains("set 3"))
    }

    // MARK: - Override weight and reps

    @Test("Overrides weight and reps when provided")
    func overridesWeightAndReps() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let context = makeContext(workout: workout)
        let tool = LogSetTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "weight": 90.0, "reps": 6, "weight_unit": "lbs"}"#,
            context: context
        )

        let sorted = workout.exercises[0].sets.sorted { $0.order < $1.order }
        #expect(sorted[0].weight == 90.0)
        #expect(sorted[0].reps == 6)
        #expect(sorted[0].weightUnit == .lbs)
        #expect(sorted[0].isCompleted == true)
        #expect(result.contains("90.0"))
    }

    // MARK: - Preserve existing values

    @Test("Preserves existing values when weight/reps not provided")
    func preservesExistingValues() async throws {
        let (workout, _) = makeWorkoutWithExercise(sets: [(80.0, 8, false)])
        let context = makeContext(workout: workout)
        let tool = LogSetTool()

        _ = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press"}"#,
            context: context
        )

        let set = workout.exercises[0].sets[0]
        #expect(set.weight == 80.0)
        #expect(set.reps == 8)
        #expect(set.isCompleted == true)
    }

    // MARK: - Error cases

    @Test("Returns error when no active workout")
    func noActiveWorkout() async throws {
        let context = makeContext(workout: nil)
        let tool = LogSetTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press"}"#,
            context: context
        )

        #expect(result.contains("No active workout"))
    }

    @Test("Returns error when exercise not found")
    func exerciseNotFound() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let context = makeContext(workout: workout)
        let tool = LogSetTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Squat"}"#,
            context: context
        )

        #expect(result.contains("not found"))
    }

    @Test("Returns informative message when all sets already complete")
    func allSetsAlreadyComplete() async throws {
        let (workout, _) = makeWorkoutWithExercise(sets: [
            (80.0, 8, true), (80.0, 8, true), (80.0, 8, true)
        ])
        let context = makeContext(workout: workout)
        let tool = LogSetTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press"}"#,
            context: context
        )

        #expect(result.lowercased().contains("already") || result.lowercased().contains("all"))
    }

    @Test("Returns error when set_number is out of range")
    func setNumberOutOfRange() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let context = makeContext(workout: workout)
        let tool = LogSetTool()

        let result = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press", "set_number": 10}"#,
            context: context
        )

        #expect(result.lowercased().contains("out of range") || result.lowercased().contains("invalid") || result.lowercased().contains("only"))
    }

    // MARK: - Save

    @Test("Saves workout after completion")
    func savesWorkout() async throws {
        let (workout, _) = makeWorkoutWithExercise()
        let workoutRepo = MockWorkoutRepository()
        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: workoutRepo,
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )
        let tool = LogSetTool()

        _ = try await tool.execute(
            inputJSON: #"{"exercise_name": "Bench Press"}"#,
            context: context
        )

        #expect(workoutRepo.saveCallCount == 1)
    }
}
