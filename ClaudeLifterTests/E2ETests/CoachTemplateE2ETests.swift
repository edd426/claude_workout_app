import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("Coach Template E2E Tests")
@MainActor
struct CoachTemplateE2ETests {

    // MARK: - Test 1: Create Template via Tool, Persist, Fetch

    @Test("coach creates template via tool, persists to SwiftData, fetchable")
    func coachCreatesTemplatePersistsAndFetchable() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Insert exercises into SwiftData
        let benchPress = TestFixtures.makeExercise(name: "Bench Press", equipment: "barbell")
        let squat = TestFixtures.makeSquat()
        context.insert(benchPress)
        context.insert(squat)
        try context.save()

        // Create real repositories
        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let workoutRepo = SwiftDataWorkoutRepository(context: context)

        let toolContext = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            activeWorkout: nil
        )

        // Build the JSON input for the tool
        let inputJSON = """
        {
          "template_name": "Push Day",
          "exercises": [
            { "name": "Bench Press", "sets": 3, "reps": 8, "weight": 80.0 },
            { "name": "Barbell Squat", "sets": 4, "reps": 5, "weight": 100.0 }
          ]
        }
        """

        let tool = CreateTemplateTool()

        // execute returns a summary (awaiting confirmation)
        let summary = try await tool.execute(inputJSON: inputJSON, context: toolContext)
        #expect(summary.contains("Push Day"))
        #expect(summary.contains("Awaiting confirmation"))

        // Build the real template (simulates the confirmation flow)
        let template = try await tool.buildTemplate(inputJSON: inputJSON, exerciseRepository: exerciseRepo)
        let builtTemplate = try #require(template)
        #expect(builtTemplate.name == "Push Day")
        #expect(builtTemplate.exercises.count == 2)

        // Save via real repository
        try await templateRepo.save(builtTemplate)

        // Fetch back and verify
        let allTemplates = try await templateRepo.fetchAll()
        #expect(allTemplates.count == 1)

        let saved = try #require(allTemplates.first)
        #expect(saved.name == "Push Day")
        #expect(saved.exercises.count == 2)

        let sortedExercises = saved.exercises.sorted { $0.order < $1.order }
        let firstTE = try #require(sortedExercises.first)
        #expect(firstTE.defaultSets == 3)
        #expect(firstTE.defaultReps == 8)
        #expect(firstTE.defaultWeight == 80.0)
        #expect(firstTE.exercise?.name == "Bench Press")

        let secondTE = sortedExercises[1]
        #expect(secondTE.defaultSets == 4)
        #expect(secondTE.defaultReps == 5)
        #expect(secondTE.defaultWeight == 100.0)
        #expect(secondTE.exercise?.name == "Barbell Squat")
    }

    // MARK: - Test 2: Create Program with Multiple Templates, All Persist

    @Test("coach creates program with multiple templates, all persist")
    func coachCreatesProgramAllTemplatesPersist() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Insert exercises
        let benchPress = TestFixtures.makeExercise(name: "Bench Press", equipment: "barbell")
        let squat = TestFixtures.makeSquat()
        let deadlift = TestFixtures.makeDeadlift()
        context.insert(benchPress)
        context.insert(squat)
        context.insert(deadlift)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let workoutRepo = SwiftDataWorkoutRepository(context: context)

        let toolContext = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            activeWorkout: nil
        )

        let inputJSON = """
        {
          "program_name": "Upper/Lower Split",
          "templates": [
            {
              "template_name": "Upper Day",
              "exercises": [
                { "name": "Bench Press", "sets": 4, "reps": 8 }
              ]
            },
            {
              "template_name": "Lower Day",
              "exercises": [
                { "name": "Barbell Squat", "sets": 4, "reps": 5 },
                { "name": "Deadlift", "sets": 3, "reps": 5 }
              ]
            }
          ]
        }
        """

        let tool = CreateProgramTool()

        // execute returns a summary awaiting confirmation
        let summary = try await tool.execute(inputJSON: inputJSON, context: toolContext)
        #expect(summary.contains("Upper/Lower Split"))
        #expect(summary.contains("Awaiting confirmation"))

        // Build all templates
        let templates = try await tool.buildTemplates(inputJSON: inputJSON, exerciseRepository: exerciseRepo)
        #expect(templates.count == 2)

        // Save each template via the repository
        for template in templates {
            try await templateRepo.save(template)
        }

        // Fetch back and verify all templates are present
        let allTemplates = try await templateRepo.fetchAll()
        #expect(allTemplates.count == 2)

        let templateNames = allTemplates.map { $0.name }
        #expect(templateNames.contains("Upper Day"))
        #expect(templateNames.contains("Lower Day"))

        let upperDay = try #require(allTemplates.first { $0.name == "Upper Day" })
        #expect(upperDay.exercises.count == 1)
        #expect(upperDay.exercises.first?.exercise?.name == "Bench Press")

        let lowerDay = try #require(allTemplates.first { $0.name == "Lower Day" })
        #expect(lowerDay.exercises.count == 2)
    }

    // MARK: - Test 3: Modify Existing Template, Changes Persist

    @Test("coach modifies existing template via tool, changes persist")
    func coachModifiesExistingTemplatePersists() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Insert exercises
        let benchPress = TestFixtures.makeExercise(name: "Bench Press", equipment: "barbell")
        let overhead = TestFixtures.makeExercise(name: "Overhead Press", equipment: "barbell")
        context.insert(benchPress)
        context.insert(overhead)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let workoutRepo = SwiftDataWorkoutRepository(context: context)

        // Create and save a starting template with 1 exercise
        let initialTemplate = WorkoutTemplate(name: "Push Day")
        let te = TemplateExercise(
            order: 0,
            exercise: benchPress,
            defaultSets: 3,
            defaultReps: 8,
            defaultWeight: 80.0
        )
        initialTemplate.exercises.append(te)
        context.insert(initialTemplate)
        try context.save()

        // Verify initial state
        let beforeTemplates = try await templateRepo.fetchAll()
        let beforeTemplate = try #require(beforeTemplates.first { $0.name == "Push Day" })
        #expect(beforeTemplate.exercises.count == 1)

        let toolContext = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            activeWorkout: nil
        )

        let inputJSON = """
        {
          "template_name": "Push Day",
          "action": "add_exercise",
          "exercise_name": "Overhead Press",
          "sets": 3,
          "reps": 10
        }
        """

        let tool = ModifyTemplateTool()

        // execute returns a confirmation prompt
        let summary = try await tool.execute(inputJSON: inputJSON, context: toolContext)
        #expect(summary.contains("Overhead Press"))
        #expect(summary.contains("Awaiting confirmation"))

        // Apply the modification (simulates confirmation)
        let result = try await tool.applyAndSave(
            inputJSON: inputJSON,
            templateRepository: templateRepo,
            exerciseRepository: exerciseRepo
        )
        #expect(result.contains("Overhead Press"))

        // Fetch back and verify the template now has 2 exercises
        let afterTemplates = try await templateRepo.fetchAll()
        let afterTemplate = try #require(afterTemplates.first { $0.name == "Push Day" })
        #expect(afterTemplate.exercises.count == 2)

        let exerciseNames = afterTemplate.exercises.compactMap { $0.exercise?.name }
        #expect(exerciseNames.contains("Bench Press"))
        #expect(exerciseNames.contains("Overhead Press"))
    }
}
