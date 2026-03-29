import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

// MARK: - GetExerciseHistoryTool Tests

@Suite("GetExerciseHistoryTool Tests")
@MainActor
struct GetExerciseHistoryToolTests {

    func makeContext(
        exercises: [Exercise] = [],
        recentSets: [WorkoutSet] = [],
        workouts: [Workout] = []
    ) -> ToolContext {
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = exercises

        let workoutRepo = MockWorkoutRepository()
        workoutRepo.recentSetsResult = recentSets
        workoutRepo.workouts = workouts

        return ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
    }

    @Test("Returns history for known exercise with sets")
    func returnsHistory() async throws {
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        let sets = [
            WorkoutSet(order: 0, weight: 80.0, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: .now),
            WorkoutSet(order: 1, weight: 80.0, weightUnit: .kg, reps: 7, isCompleted: true, completedAt: .now)
        ]
        let context = makeContext(exercises: [exercise], recentSets: sets)
        let tool = GetExerciseHistoryTool()

        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Bench Press\"}", context: context)

        #expect(result.contains("Bench Press"))
        #expect(result.contains("80.0"))
    }

    @Test("Returns no history message when exercise has no sets")
    func returnsNoHistoryMessage() async throws {
        let exercise = TestFixtures.makeExercise(name: "Squat")
        let context = makeContext(exercises: [exercise], recentSets: [])
        let tool = GetExerciseHistoryTool()

        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Squat\"}", context: context)
        #expect(result.contains("No history"))
    }

    @Test("Returns error when exercise not found")
    func returnsErrorForUnknownExercise() async throws {
        let context = makeContext(exercises: [])
        let tool = GetExerciseHistoryTool()

        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Unknown Exercise\"}", context: context)
        #expect(result.contains("No exercise found"))
    }

    @Test("Returns error when exercise_name missing")
    func returnsErrorWhenMissingParam() async throws {
        let context = makeContext()
        let tool = GetExerciseHistoryTool()
        let result = try await tool.execute(inputJSON: "{}", context: context)
        #expect(result.contains("Error"))
    }
}

// MARK: - GetRecentWorkoutsTool Tests

@Suite("GetRecentWorkoutsTool Tests")
@MainActor
struct GetRecentWorkoutsToolTests {

    @Test("Returns message when no workouts")
    func returnsEmptyMessage() async throws {
        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
        let tool = GetRecentWorkoutsTool()
        let result = try await tool.execute(inputJSON: "{}", context: context)
        #expect(result.contains("No workouts"))
    }

    @Test("Returns workout summaries")
    func returnsWorkoutSummaries() async throws {
        let workoutRepo = MockWorkoutRepository()
        workoutRepo.workouts = [
            Workout(name: "Push Day", startedAt: Date(), completedAt: Date()),
            Workout(name: "Pull Day", startedAt: Date(), completedAt: Date())
        ]
        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: workoutRepo,
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
        let tool = GetRecentWorkoutsTool()
        let result = try await tool.execute(inputJSON: "{\"limit\": 5}", context: context)
        #expect(result.contains("Push Day"))
        #expect(result.contains("Pull Day"))
    }

    @Test("Respects limit parameter")
    func respectsLimit() async throws {
        let workoutRepo = MockWorkoutRepository()
        workoutRepo.workouts = [
            Workout(name: "Workout A", startedAt: Date()),
            Workout(name: "Workout B", startedAt: Date()),
            Workout(name: "Workout C", startedAt: Date())
        ]
        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: workoutRepo,
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
        let tool = GetRecentWorkoutsTool()
        let result = try await tool.execute(inputJSON: "{\"limit\": 2}", context: context)
        #expect(result.contains("Workout A"))
        #expect(result.contains("Workout B"))
        #expect(!result.contains("Workout C"))
    }
}

// MARK: - SuggestWeightTool Tests

@Suite("SuggestWeightTool Tests")
@MainActor
struct SuggestWeightToolTests {

    @Test("Returns suggestion based on last session sets")
    func returnsSuggestion() async throws {
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = [exercise]

        let workoutRepo = MockWorkoutRepository()
        workoutRepo.recentSetsResult = [
            WorkoutSet(order: 0, weight: 100.0, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: .now)
        ]
        // Recent workout for time-since-last check
        let workout = Workout(name: "Push Day", startedAt: Date(timeIntervalSinceNow: -86400))
        let we = WorkoutExercise(order: 0, exercise: exercise)
        workout.exercises = [we]
        workoutRepo.workouts = [workout]

        let context = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
        let tool = SuggestWeightTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Bench Press\"}", context: context)
        #expect(result.contains("Bench Press"))
        #expect(result.contains("kg"))
    }

    @Test("Returns no-history message for exercise with no sets")
    func returnsNoHistoryMessage() async throws {
        let exercise = TestFixtures.makeExercise(name: "New Exercise")
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = [exercise]

        let context = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
        let tool = SuggestWeightTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"New Exercise\"}", context: context)
        #expect(result.contains("No history"))
    }

    @Test("Returns error for unknown exercise")
    func returnsErrorForUnknownExercise() async throws {
        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
        let tool = SuggestWeightTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Unknown\"}", context: context)
        #expect(result.contains("No exercise found"))
    }
}

// MARK: - AddExerciseTool Tests

@Suite("AddExerciseTool Tests")
@MainActor
struct AddExerciseToolTests {

    @Test("Adds exercise to active workout")
    func addsExercise() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Tricep Pushdown")
        context.insert(exercise)

        let workout = Workout(name: "Push Day", startedAt: .now)
        context.insert(workout)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let workoutRepo = SwiftDataWorkoutRepository(context: context)

        let toolContext = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )

        let tool = AddExerciseTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Tricep Pushdown\"}", context: toolContext)

        #expect(result.contains("Added"))
        #expect(result.contains("Tricep Pushdown"))
        #expect(workout.exercises.count == 1)
    }

    @Test("Returns error when no active workout")
    func returnsErrorWhenNoWorkout() async throws {
        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
        let tool = AddExerciseTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Squat\"}", context: context)
        #expect(result.contains("No active workout"))
    }

    @Test("Returns already-in-workout message for duplicate")
    func returnsDuplicateMessage() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let workout = Workout(name: "Push Day", startedAt: .now)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        workout.exercises = [we]
        context.insert(workout)
        try context.save()

        let toolContext = ToolContext(
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )

        let tool = AddExerciseTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Bench Press\"}", context: toolContext)
        #expect(result.contains("already"))
    }
}

// MARK: - RemoveExerciseTool Tests

@Suite("RemoveExerciseTool Tests")
@MainActor
struct RemoveExerciseToolTests {

    @Test("Removes exercise from active workout")
    func removesExercise() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Leg Press")
        context.insert(exercise)

        let workout = Workout(name: "Leg Day", startedAt: .now)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        workout.exercises = [we]
        context.insert(workout)
        try context.save()

        let toolContext = ToolContext(
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )

        let tool = RemoveExerciseTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Leg Press\"}", context: toolContext)

        #expect(result.contains("Removed"))
        #expect(workout.exercises.isEmpty)
    }

    @Test("Returns not-found message when exercise not in workout")
    func returnsNotFoundMessage() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let workout = Workout(name: "Push Day", startedAt: .now)
        context.insert(workout)
        try context.save()

        let toolContext = ToolContext(
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )

        let tool = RemoveExerciseTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Nonexistent\"}", context: toolContext)
        #expect(result.contains("not found"))
    }

    @Test("Returns error when no active workout")
    func returnsErrorWhenNoWorkout() async throws {
        let toolContext = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
        let tool = RemoveExerciseTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Squat\"}", context: toolContext)
        #expect(result.contains("No active workout"))
    }
}
