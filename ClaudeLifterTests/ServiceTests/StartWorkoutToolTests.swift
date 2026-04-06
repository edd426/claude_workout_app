import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("StartWorkoutTool Tests")
@MainActor
struct StartWorkoutToolTests {

    // MARK: - Helpers

    private func makeTemplate(name: String, exerciseCount: Int = 3) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: name)
        for i in 0..<exerciseCount {
            let exercise = TestFixtures.makeExercise(name: "Exercise \(i + 1)")
            let te = TemplateExercise(order: i, exercise: exercise, defaultSets: 3, defaultReps: 8)
            template.exercises.append(te)
        }
        return template
    }

    private func makeContext(
        templates: [WorkoutTemplate] = [],
        activeWorkout: Workout? = nil,
        onStartWorkout: (@MainActor @Sendable (WorkoutTemplate) async -> Void)? = nil
    ) -> ToolContext {
        let templateRepo = MockTemplateRepository()
        templateRepo.templates = templates
        return ToolContext(
            exerciseRepository: MockExerciseRepository(),
            workoutRepository: MockWorkoutRepository(),
            templateRepository: templateRepo,
            activeWorkout: activeWorkout,
            onStartWorkout: onStartWorkout
        )
    }

    // MARK: - Exact name match

    @Test("Finds template by exact name and calls callback")
    func findsTemplateByExactName() async throws {
        let template = makeTemplate(name: "Push Day")
        var callbackTemplate: WorkoutTemplate?
        let context = makeContext(
            templates: [template],
            onStartWorkout: { t in callbackTemplate = t }
        )
        let tool = StartWorkoutTool()

        let result = try await tool.execute(
            inputJSON: #"{"template_name": "Push Day"}"#,
            context: context
        )

        #expect(callbackTemplate?.id == template.id)
        #expect(result.contains("Started workout"))
        #expect(result.contains("Push Day"))
        #expect(result.contains("3 exercises"))
    }

    // MARK: - Case-insensitive match

    @Test("Fuzzy matches template name case-insensitively")
    func fuzzyMatchesCaseInsensitive() async throws {
        let template = makeTemplate(name: "Upper Body Pull")
        var callbackCalled = false
        let context = makeContext(
            templates: [template],
            onStartWorkout: { _ in callbackCalled = true }
        )
        let tool = StartWorkoutTool()

        let result = try await tool.execute(
            inputJSON: #"{"template_name": "upper body pull"}"#,
            context: context
        )

        #expect(callbackCalled)
        #expect(result.contains("Started workout"))
    }

    // MARK: - Contains match

    @Test("Matches template by partial name when unambiguous")
    func matchesByPartialName() async throws {
        let template = makeTemplate(name: "Wednesday Push Day")
        var callbackCalled = false
        let context = makeContext(
            templates: [template],
            onStartWorkout: { _ in callbackCalled = true }
        )
        let tool = StartWorkoutTool()

        let result = try await tool.execute(
            inputJSON: #"{"template_name": "push day"}"#,
            context: context
        )

        #expect(callbackCalled)
        #expect(result.contains("Started workout"))
    }

    // MARK: - No matching template

    @Test("No matching template returns error with available templates")
    func noMatchingTemplate() async throws {
        let t1 = makeTemplate(name: "Push Day")
        let t2 = makeTemplate(name: "Pull Day")
        let context = makeContext(templates: [t1, t2])
        let tool = StartWorkoutTool()

        let result = try await tool.execute(
            inputJSON: #"{"template_name": "Leg Day"}"#,
            context: context
        )

        #expect(result.contains("No template found"))
        #expect(result.contains("Leg Day"))
        #expect(result.contains("Push Day"))
        #expect(result.contains("Pull Day"))
    }

    // MARK: - Workout already active

    @Test("Workout already active returns error message")
    func workoutAlreadyActive() async throws {
        let template = makeTemplate(name: "Push Day")
        let activeWorkout = Workout(name: "Current Workout", startedAt: .now)
        let context = makeContext(
            templates: [template],
            activeWorkout: activeWorkout
        )
        let tool = StartWorkoutTool()

        let result = try await tool.execute(
            inputJSON: #"{"template_name": "Push Day"}"#,
            context: context
        )

        #expect(result.contains("already have an active workout"))
    }

    // MARK: - Multiple ambiguous matches

    @Test("Multiple ambiguous matches returns disambiguation message")
    func multipleAmbiguousMatches() async throws {
        let t1 = makeTemplate(name: "Push Day A")
        let t2 = makeTemplate(name: "Push Day B")
        let context = makeContext(templates: [t1, t2])
        let tool = StartWorkoutTool()

        let result = try await tool.execute(
            inputJSON: #"{"template_name": "Push Day"}"#,
            context: context
        )

        #expect(result.contains("Multiple templates match"))
        #expect(result.contains("Push Day A"))
        #expect(result.contains("Push Day B"))
    }

    // MARK: - Nil callback

    @Test("Nil callback returns graceful error")
    func nilCallbackReturnsError() async throws {
        let template = makeTemplate(name: "Push Day")
        let context = makeContext(
            templates: [template],
            onStartWorkout: nil
        )
        let tool = StartWorkoutTool()

        let result = try await tool.execute(
            inputJSON: #"{"template_name": "Push Day"}"#,
            context: context
        )

        #expect(result.contains("Unable to start workout"))
    }

    // MARK: - Missing parameter

    @Test("Missing template_name parameter returns error")
    func missingParameter() async throws {
        let context = makeContext()
        let tool = StartWorkoutTool()

        let result = try await tool.execute(
            inputJSON: #"{}"#,
            context: context
        )

        #expect(result.contains("Error"))
        #expect(result.contains("template_name"))
    }
}
