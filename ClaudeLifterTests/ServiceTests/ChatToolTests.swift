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

// MARK: - CreateTemplateTool Tests

@Suite("CreateTemplateTool Tests")
@MainActor
struct CreateTemplateToolTests {

    func makeContext(exercises: [Exercise] = []) -> ToolContext {
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = exercises
        return ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
    }

    @Test("Returns error when template_name is missing")
    func requiresTemplateName() async throws {
        let context = makeContext()
        let tool = CreateTemplateTool()
        let result = try await tool.execute(inputJSON: "{\"exercises\": []}", context: context)
        #expect(result.contains("Error"))
    }

    @Test("Creates template with matching exercises")
    func createsTemplateWithExercises() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let ohp = TestFixtures.makeExercise(name: "Overhead Press")
        let context = makeContext(exercises: [bench, ohp])
        let tool = CreateTemplateTool()

        let input = """
        {
          "template_name": "Push Day",
          "exercises": [
            {"name": "Bench Press", "sets": 3, "reps": 8},
            {"name": "Overhead Press", "sets": 3, "reps": 10}
          ]
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("Push Day"))
        #expect(result.contains("Bench Press"))
        #expect(result.contains("Overhead Press"))
    }

    @Test("Returns confirmation summary awaiting confirmation")
    func returnsConfirmationSummary() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let triceps = TestFixtures.makeExercise(name: "Tricep Pushdown")
        let context = makeContext(exercises: [bench, triceps])
        let tool = CreateTemplateTool()

        let input = """
        {
          "template_name": "Push Day",
          "exercises": [
            {"name": "Bench Press", "sets": 3, "reps": 8},
            {"name": "Tricep Pushdown", "sets": 3, "reps": 12}
          ]
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.lowercased().contains("awaiting confirmation") || result.lowercased().contains("confirm"))
    }

    @Test("Handles missing exercise gracefully by skipping it")
    func handlesMissingExerciseGracefully() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let context = makeContext(exercises: [bench])
        let tool = CreateTemplateTool()

        let input = """
        {
          "template_name": "Push Day",
          "exercises": [
            {"name": "Bench Press", "sets": 3, "reps": 8},
            {"name": "Unknown Exercise XYZ", "sets": 3, "reps": 10}
          ]
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        // Should still succeed with the found exercise
        #expect(result.contains("Bench Press"))
        // Should not crash or return a hard error
        #expect(!result.hasPrefix("Error: missing required"))
    }

    @Test("Sets correct default values for sets and reps")
    func setsCorrectDefaultValues() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let context = makeContext(exercises: [bench])
        let tool = CreateTemplateTool()

        let input = """
        {
          "template_name": "Quick Push",
          "exercises": [
            {"name": "Bench Press", "sets": 4, "reps": 6, "weight": 100.0}
          ]
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("4"))
        #expect(result.contains("6"))
    }

    @Test("buildTemplate persists template to repository when confirmed")
    func buildTemplatePersistsToRepository() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = [bench]
        let templateRepo = MockTemplateRepository()
        let tool = CreateTemplateTool()

        let input = """
        {
          "template_name": "Push Day",
          "exercises": [
            {"name": "Bench Press", "sets": 3, "reps": 8}
          ]
        }
        """

        guard let template = try await tool.buildTemplate(inputJSON: input, exerciseRepository: exerciseRepo) else {
            Issue.record("buildTemplate returned nil")
            return
        }
        try await templateRepo.save(template)

        #expect(templateRepo.saveCallCount == 1)
        #expect(templateRepo.savedTemplates.count == 1)
        #expect(templateRepo.savedTemplates.first?.name == "Push Day")
        #expect(templateRepo.savedTemplates.first?.exercises.count == 1)
    }

    @Test("create_template auto-saves template via ChatViewModel executeTool")
    func createTemplateAutoSavesViaViewModel() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = [bench]
        let templateRepo = MockTemplateRepository()

        let anthropicService = MockAnthropicService()
        anthropicService.stubbedEventSequences = [
            [
                .toolUse(id: "t1", name: "create_template", inputJSON: """
                {"template_name": "Upper Body", "exercises": [{"name": "Bench Press", "sets": 4, "reps": 6}]}
                """),
                .complete
            ],
            [.text("Template created."), .complete]
        ]

        let vm = ChatViewModel(
            anthropicService: anthropicService,
            exerciseRepository: exerciseRepo,
            workoutRepository: MockWorkoutRepository(),
            templateRepository: templateRepo,
            preferenceRepository: MockTrainingPreferenceRepository()
        )

        await vm.sendMessage("Create an upper body template")

        // Template should be auto-saved without any confirmation step
        #expect(templateRepo.saveCallCount == 1)
        #expect(templateRepo.savedTemplates.first?.name == "Upper Body")
    }

    // MARK: - Issue #57: 0-exercise error handling

    @Test("execute returns error message when no exercises match — not awaiting confirmation")
    func executeReturnsErrorWhenNoExercisesMatch() async throws {
        // Arrange: empty exercise library
        let context = makeContext(exercises: [])
        let tool = CreateTemplateTool()

        let input = """
        {
          "template_name": "Push Day",
          "exercises": [
            {"name": "Unknown Exercise A", "sets": 3, "reps": 8},
            {"name": "Unknown Exercise B", "sets": 3, "reps": 10}
          ]
        }
        """

        // Act
        let result = try await tool.execute(inputJSON: input, context: context)

        // Assert: should be an error message, NOT "Awaiting confirmation"
        #expect(!result.lowercased().contains("awaiting confirmation"))
        #expect(result.lowercased().contains("error") || result.lowercased().contains("no matching") || result.lowercased().contains("could not"))
    }

    @Test("buildTemplate returns nil when no exercises match")
    func buildTemplateReturnsNilWhenZeroExercises() async throws {
        // Arrange: empty exercise library, so nothing resolves
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = []
        let tool = CreateTemplateTool()

        let input = """
        {
          "template_name": "Impossible Day",
          "exercises": [
            {"name": "Unknown Exercise", "sets": 3, "reps": 8}
          ]
        }
        """

        // Act
        let result = try await tool.buildTemplate(inputJSON: input, exerciseRepository: exerciseRepo)

        // Assert: nil when no exercises matched
        #expect(result == nil)
    }
}

// MARK: - CreateProgramTool Tests

@Suite("CreateProgramTool Tests")
@MainActor
struct CreateProgramToolTests {

    func makeContext(exercises: [Exercise] = []) -> ToolContext {
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = exercises
        return ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )
    }

    @Test("Creates multiple templates from program input")
    func createsMultipleTemplates() async throws {
        let squat = TestFixtures.makeExercise(name: "Squat")
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let context = makeContext(exercises: [squat, bench])
        let tool = CreateProgramTool()

        let input = """
        {
          "program_name": "PPL",
          "templates": [
            {
              "template_name": "Push",
              "exercises": [{"name": "Bench Press", "sets": 3, "reps": 8}]
            },
            {
              "template_name": "Legs",
              "exercises": [{"name": "Squat", "sets": 4, "reps": 6}]
            }
          ]
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("Push"))
        #expect(result.contains("Legs"))
    }

    @Test("Returns error when templates array is empty")
    func requiresAtLeastOneTemplate() async throws {
        let context = makeContext()
        let tool = CreateProgramTool()

        let input = """
        {
          "program_name": "Empty Program",
          "templates": []
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("Error") || result.contains("at least"))
    }

    @Test("Returns full program summary with all template names")
    func returnsProgramSummary() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let deadlift = TestFixtures.makeExercise(name: "Deadlift")
        let context = makeContext(exercises: [bench, deadlift])
        let tool = CreateProgramTool()

        let input = """
        {
          "program_name": "Strength Block",
          "templates": [
            {
              "template_name": "Push Day",
              "exercises": [{"name": "Bench Press", "sets": 3, "reps": 5}]
            },
            {
              "template_name": "Pull Day",
              "exercises": [{"name": "Deadlift", "sets": 3, "reps": 5}]
            }
          ]
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("Strength Block"))
        #expect(result.contains("Push Day"))
        #expect(result.contains("Pull Day"))
    }

    @Test("Returns error when program_name is missing")
    func requiresProgramName() async throws {
        let context = makeContext()
        let tool = CreateProgramTool()

        let input = """
        {
          "templates": [
            {"template_name": "Push", "exercises": []}
          ]
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("Error"))
    }

    // MARK: - Issue #58: 0-exercise error handling for programs

    @Test("Returns error when ALL templates have no matching exercises")
    func returnsErrorWhenAllTemplatesHaveZeroExercises() async throws {
        // Arrange: empty exercise library — nothing will match
        let context = makeContext(exercises: [])
        let tool = CreateProgramTool()

        let input = """
        {
          "program_name": "Ghost Program",
          "templates": [
            {
              "template_name": "Day A",
              "exercises": [{"name": "Unknown Exercise A", "sets": 3, "reps": 8}]
            },
            {
              "template_name": "Day B",
              "exercises": [{"name": "Unknown Exercise B", "sets": 3, "reps": 10}]
            }
          ]
        }
        """

        // Act
        let result = try await tool.execute(inputJSON: input, context: context)

        // Assert: should be an error, NOT "Awaiting confirmation"
        #expect(!result.lowercased().contains("awaiting confirmation"))
        #expect(result.lowercased().contains("error") || result.lowercased().contains("no exercises matched") || result.lowercased().contains("could not"))
    }

    @Test("Returns warning for empty templates but still confirms when some templates have exercises")
    func returnsWarningForPartiallyEmptyProgram() async throws {
        // Arrange: only exercises for one of two templates
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let context = makeContext(exercises: [bench])
        let tool = CreateProgramTool()

        let input = """
        {
          "program_name": "Partial Program",
          "templates": [
            {
              "template_name": "Push Day",
              "exercises": [{"name": "Bench Press", "sets": 3, "reps": 8}]
            },
            {
              "template_name": "Unknown Day",
              "exercises": [{"name": "Totally Unknown Exercise XYZ", "sets": 3, "reps": 10}]
            }
          ]
        }
        """

        // Act
        let result = try await tool.execute(inputJSON: input, context: context)

        // Assert: result should still say awaiting confirmation (partial success)
        #expect(result.lowercased().contains("awaiting confirmation") || result.lowercased().contains("confirm"))
        // And should warn about the empty template
        #expect(result.lowercased().contains("warning") || result.lowercased().contains("no matched") || result.lowercased().contains("skipped"))
    }
}

// MARK: - ModifyTemplateTool Tests

@Suite("ModifyTemplateTool Tests")
@MainActor
struct ModifyTemplateToolTests {

    @Test("Returns error when template_name is missing")
    func requiresTemplateName() async throws {
        let templateRepo = MockTemplateRepository()
        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: MockWorkoutRepository(),
            templateRepository: templateRepo,
            activeWorkout: nil
        )
        let tool = ModifyTemplateTool()
        let result = try await tool.execute(inputJSON: "{\"action\": \"rename\", \"new_name\": \"New\"}", context: context)
        #expect(result.contains("Error"))
    }

    @Test("add_exercise appends exercise to template")
    func addExerciseAppendsToTemplate() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = [bench]

        let template = WorkoutTemplate(name: "Push Day")
        let templateRepo = MockTemplateRepository()
        templateRepo.templates = [template]

        let context = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: MockWorkoutRepository(),
            templateRepository: templateRepo,
            activeWorkout: nil
        )
        let tool = ModifyTemplateTool()

        let input = """
        {
          "template_name": "Push Day",
          "action": "add_exercise",
          "exercise_name": "Bench Press",
          "sets": 3,
          "reps": 8
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("Bench Press"))
        #expect(result.lowercased().contains("confirm") || result.lowercased().contains("awaiting"))
    }

    @Test("remove_exercise removes exercise from template")
    func removeExerciseRemovesFromTemplate() async throws {
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = [bench]

        let template = WorkoutTemplate(name: "Push Day")
        let te = TemplateExercise(order: 0, exercise: bench, defaultSets: 3, defaultReps: 8)
        template.exercises = [te]

        let templateRepo = MockTemplateRepository()
        templateRepo.templates = [template]

        let context = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: MockWorkoutRepository(),
            templateRepository: templateRepo,
            activeWorkout: nil
        )
        let tool = ModifyTemplateTool()

        let input = """
        {
          "template_name": "Push Day",
          "action": "remove_exercise",
          "exercise_name": "Bench Press"
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("Bench Press"))
        #expect(result.lowercased().contains("confirm") || result.lowercased().contains("awaiting"))
    }

    @Test("rename updates template name in summary")
    func renameUpdatesTemplateName() async throws {
        let template = WorkoutTemplate(name: "Old Name")
        let templateRepo = MockTemplateRepository()
        templateRepo.templates = [template]

        let context = ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: MockWorkoutRepository(),
            templateRepository: templateRepo,
            activeWorkout: nil
        )
        let tool = ModifyTemplateTool()

        let input = """
        {
          "template_name": "Old Name",
          "action": "rename",
          "new_name": "New Name"
        }
        """
        let result = try await tool.execute(inputJSON: input, context: context)
        #expect(result.contains("New Name"))
        #expect(result.lowercased().contains("confirm") || result.lowercased().contains("awaiting"))
    }
}

// MARK: - Disambiguation Tests (#38 fix)

@Suite("Exercise Disambiguation Tests")
@MainActor
struct ExerciseDisambiguationTests {

    // MARK: - AddExerciseTool disambiguation

    @Test("AddExerciseTool uses exact match when available instead of first result")
    func addExerciseUsesExactMatch() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let benchPress = TestFixtures.makeExercise(name: "Bench Press")
        let overheadPress = TestFixtures.makeExercise(name: "Overhead Press")
        context.insert(benchPress)
        context.insert(overheadPress)

        let workout = Workout(name: "Push Day", startedAt: .now)
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

        #expect(result.contains("Bench Press"))
        #expect(workout.exercises.first?.exercise?.name == "Bench Press")
    }

    @Test("AddExerciseTool returns disambiguation message when multiple matches and no exact match")
    func addExerciseDisambiguatesMultipleMatches() async throws {
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = [
            TestFixtures.makeExercise(name: "Bench Press"),
            TestFixtures.makeExercise(name: "Overhead Press"),
            TestFixtures.makeExercise(name: "Incline Press")
        ]

        let workout = Workout(name: "Push Day", startedAt: .now)
        let toolContext = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )

        let tool = AddExerciseTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Press\"}", context: toolContext)

        // Should return disambiguation — not silently pick the first
        #expect(result.lowercased().contains("multiple") || result.lowercased().contains("did you mean") || result.lowercased().contains("which"))
    }

    // MARK: - SuggestWeightTool disambiguation

    @Test("SuggestWeightTool uses exact match when available")
    func suggestWeightUsesExactMatch() async throws {
        let exerciseRepo = MockExerciseRepository()
        let benchPress = TestFixtures.makeExercise(name: "Bench Press")
        let inclineBench = TestFixtures.makeExercise(name: "Incline Bench Press")
        exerciseRepo.exercises = [benchPress, inclineBench]

        let workoutRepo = MockWorkoutRepository()
        workoutRepo.recentSetsResult = [
            WorkoutSet(order: 0, weight: 100.0, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: .now)
        ]
        workoutRepo.workouts = []

        let toolContext = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )

        let tool = SuggestWeightTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Bench Press\"}", context: toolContext)

        #expect(result.contains("Bench Press"))
        #expect(result.contains("100"))
    }

    @Test("SuggestWeightTool returns disambiguation when multiple matches and no exact match")
    func suggestWeightDisambiguatesMultipleMatches() async throws {
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = [
            TestFixtures.makeExercise(name: "Bench Press"),
            TestFixtures.makeExercise(name: "Incline Bench Press"),
            TestFixtures.makeExercise(name: "Decline Bench Press")
        ]

        let toolContext = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: MockWorkoutRepository(),
            templateRepository: MockTemplateRepository(),
            activeWorkout: nil
        )

        let tool = SuggestWeightTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Bench\"}", context: toolContext)

        #expect(result.lowercased().contains("multiple") || result.lowercased().contains("did you mean") || result.lowercased().contains("which"))
    }

    // MARK: - RemoveExerciseTool disambiguation

    @Test("RemoveExerciseTool uses exact workout match when available")
    func removeExerciseUsesExactWorkoutMatch() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let benchPress = TestFixtures.makeExercise(name: "Bench Press")
        let inclineBench = TestFixtures.makeExercise(name: "Incline Bench Press")
        context.insert(benchPress)
        context.insert(inclineBench)

        let workout = Workout(name: "Push Day", startedAt: .now)
        let we1 = WorkoutExercise(order: 0, exercise: benchPress)
        let we2 = WorkoutExercise(order: 1, exercise: inclineBench)
        context.insert(we1)
        context.insert(we2)
        workout.exercises = [we1, we2]
        context.insert(workout)
        try context.save()

        let toolContext = ToolContext(
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: MockTemplateRepository(),
            activeWorkout: workout
        )

        let tool = RemoveExerciseTool()
        let result = try await tool.execute(inputJSON: "{\"exercise_name\": \"Bench Press\"}", context: toolContext)

        #expect(result.lowercased().contains("removed"))
        #expect(workout.exercises.count == 1)
        #expect(workout.exercises.first?.exercise?.name == "Incline Bench Press")
    }

    // MARK: - CreateTemplateTool disambiguation

    @Test("CreateTemplateTool uses exact match for exercises when building template")
    func createTemplateUsesExactMatch() async throws {
        let exerciseRepo = MockExerciseRepository()
        let benchPress = TestFixtures.makeExercise(name: "Bench Press")
        let inclineBench = TestFixtures.makeExercise(name: "Incline Bench Press")
        exerciseRepo.exercises = [benchPress, inclineBench]

        let tool = CreateTemplateTool()
        let input = """
        {
          "template_name": "Push Day",
          "exercises": [{"name": "Bench Press", "sets": 3, "reps": 8}]
        }
        """

        let template = try await tool.buildTemplate(inputJSON: input, exerciseRepository: exerciseRepo)
        #expect(template?.exercises.count == 1)
        #expect(template?.exercises.first?.exercise?.name == "Bench Press")
    }
}

// MARK: - Exercise Array Normalization Tests

@Suite("Exercise Array Normalization Tests")
@MainActor
struct ExerciseArrayNormalizationTests {

    @Test("normalizeExercises handles array of objects (standard format)")
    func normalizesObjectArray() {
        let json: [String: Any] = [
            "exercises": [
                ["name": "Squat", "sets": 3, "reps": 8] as [String: Any],
                ["name": "Bench Press", "sets": 4, "reps": 6] as [String: Any]
            ]
        ]
        let result = CreateTemplateTool.normalizeExercises(from: json)
        #expect(result.count == 2)
        #expect(result[0]["name"] as? String == "Squat")
        #expect(result[1]["sets"] as? Int == 4)
    }

    @Test("normalizeExercises handles array of strings (Claude's actual format)")
    func normalizesStringArray() {
        let json: [String: Any] = [
            "exercises": ["Barbell Squat", "Barbell Bench Press - Medium Grip", "Barbell Deadlift"]
        ]
        let result = CreateTemplateTool.normalizeExercises(from: json)
        #expect(result.count == 3)
        #expect(result[0]["name"] as? String == "Barbell Squat")
        #expect(result[1]["name"] as? String == "Barbell Bench Press - Medium Grip")
        #expect(result[2]["name"] as? String == "Barbell Deadlift")
    }

    @Test("normalizeExercises returns empty for missing field")
    func normalizesEmptyWhenMissing() {
        let json: [String: Any] = ["template_name": "Test"]
        let result = CreateTemplateTool.normalizeExercises(from: json)
        #expect(result.isEmpty)
    }

    @Test("create_template works with string array exercises via execute")
    func createTemplateWithStringArray() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let squat = TestFixtures.makeExercise(name: "Barbell Squat")
        let bench = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(squat)
        context.insert(bench)
        try context.save()

        let toolContext = ToolContext(
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            activeWorkout: nil
        )

        let tool = CreateTemplateTool()
        // Simulate Claude sending exercises as string array (the bug!)
        let input = """
        {"template_name": "Test Workout", "exercises": ["Barbell Squat", "Bench Press"]}
        """

        let result = try await tool.execute(inputJSON: input, context: toolContext)
        #expect(result.contains("2 exercise(s)"), "Should match both exercises, got: \(result)")
        #expect(result.contains("Awaiting confirmation"))
        #expect(!result.contains("Error"))
    }
}
