import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

// MARK: - Integration Tests
//
// These tests use real SwiftData repositories (same ModelContext = shared state),
// MockAnthropicService (canned tool call events), and real ViewModels.
// They verify cross-boundary flows that unit tests cannot catch.

@Suite("Integration Tests", .serialized)
@MainActor
struct IntegrationTests {

    // MARK: - Helpers

    /// Load the real exercise database into the test context.
    /// Falls back to a small inline dataset if exercises.json is not available.
    private func importRealExercises(into context: ModelContext) async throws -> Bool {
        // Try main bundle first (exercises.json is bundled with ClaudeLifter)
        if let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            let service = ExerciseImportService()
            let count = try await service.importExercises(from: data, into: context)
            return count > 0
        }

        // Try test bundle (may be available when running on device)
        let testBundle = Bundle(for: type(of: ExerciseImportService()))
        if let url = testBundle.url(forResource: "exercises", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            let service = ExerciseImportService()
            let count = try await service.importExercises(from: data, into: context)
            return count > 0
        }

        return false
    }

    /// Insert a small but sufficient inline dataset. These exercise names
    /// exist verbatim in exercises.json so fuzzySearch finds them with real DB too.
    private func insertInlineExercises(into context: ModelContext) {
        let exercises: [(String, String)] = [
            ("Barbell Squat", "barbell"),
            ("Barbell Deadlift", "barbell"),
            ("Barbell Bench Press - Medium Grip", "barbell"),
            ("Barbell Curl", "barbell"),
            ("Bent Over Barbell Row", "barbell"),
            ("Dumbbell Shoulder Press", "dumbbell"),
            ("Barbell Shoulder Press", "barbell"),
            ("Barbell Incline Bench Press - Medium Grip", "barbell"),
        ]
        for (idx, (name, equip)) in exercises.enumerated() {
            let ex = TestFixtures.makeExercise(name: name, equipment: equip, externalId: "inline_\(idx)")
            context.insert(ex)
        }
        try? context.save()
    }

    // MARK: - Test 1: Coach Creates Template → Visible on Home Screen

    @Test("Coach creates template via chat tool, template appears in HomeViewModel")
    func coachCreatesTemplateVisibleOnHome() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Load real exercises; fall back to inline dataset
        let loadedReal = try await importRealExercises(into: context)
        if !loadedReal {
            insertInlineExercises(into: context)
        }

        // Shared repositories backed by the same context
        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        // Mock anthropic: call 1 returns create_template tool, call 2 returns confirmation text
        let mock = MockAnthropicService()
        mock.stubbedEventSequences = [
            // Call 1: Claude decides to create a push day template
            [
                .text("I'll create a push day template for you."),
                .toolUse(id: "t1", name: "create_template", inputJSON: """
                {
                    "template_name": "Push Day",
                    "exercises": [
                        {"name": "Barbell Squat", "sets": 4, "reps": 5},
                        {"name": "Barbell Bench Press - Medium Grip", "sets": 4, "reps": 8},
                        {"name": "Barbell Curl", "sets": 3, "reps": 12}
                    ]
                }
                """),
                .complete
            ],
            // Call 2: Claude responds after seeing tool result
            [
                .text("Your Push Day template is ready! It has 3 exercises. Tap save to confirm."),
                .complete
            ]
        ]

        let chatVM = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            preferenceRepository: prefRepo
        )

        // User sends message
        await chatVM.sendMessage("Create a push day workout for me")

        // Template should be auto-saved directly (no confirmation step needed)
        let templates = try await templateRepo.fetchAll()
        let pushDay = templates.first(where: { $0.name == "Push Day" })
        #expect(pushDay != nil, "Push Day template should be saved after confirmation")
        #expect((pushDay?.exercises.count ?? 0) > 0, "Template should have at least one matched exercise")

        // HomeViewModel with the SAME repository should see the new template
        let homeVM = HomeViewModel(templateRepository: templateRepo, workoutRepository: workoutRepo)
        await homeVM.loadTemplates()
        #expect(
            homeVM.templates.contains(where: { $0.name == "Push Day" }),
            "Home screen should show the newly created Push Day template"
        )
    }

    // MARK: - Test 2: Full Workout Session — Template → Log → Finish → History

    @Test("Full workout session: start from template, log sets, finish, verify history")
    func fullWorkoutSessionTemplateToHistory() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let loadedReal = try await importRealExercises(into: context)
        if !loadedReal {
            insertInlineExercises(into: context)
        }

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)

        // Find real exercises from the DB
        let squatMatches = try await exerciseRepo.search(query: "Barbell Squat")
        let benchMatches = try await exerciseRepo.search(query: "Barbell Bench Press - Medium Grip")

        let squat = try #require(
            squatMatches.first(where: { $0.name == "Barbell Squat" }) ?? squatMatches.first,
            "Need at least one squat exercise in the DB"
        )
        let bench = try #require(
            benchMatches.first(where: { $0.name == "Barbell Bench Press - Medium Grip" }) ?? benchMatches.first,
            "Need at least one bench press exercise in the DB"
        )

        // Create a prior workout so auto-fill has history data
        let priorWorkout = Workout(name: "Prior Push Day", startedAt: Date().addingTimeInterval(-7 * 86400), templateId: nil)
        let priorWE = WorkoutExercise(order: 0, exercise: bench)
        let priorSet = WorkoutSet(order: 0, weight: 80.0, weightUnit: .kg, reps: 8)
        priorSet.isCompleted = true
        priorSet.completedAt = Date().addingTimeInterval(-7 * 86400)
        priorWE.sets.append(priorSet)
        priorWorkout.exercises.append(priorWE)
        priorWorkout.completedAt = Date().addingTimeInterval(-7 * 86400)
        try await workoutRepo.save(priorWorkout)

        // Create a template with those 2 exercises
        let template = WorkoutTemplate(name: "Test Push Day")
        let te1 = TemplateExercise(order: 0, exercise: bench, defaultSets: 3, defaultReps: 8, defaultWeight: 80.0)
        let te2 = TemplateExercise(order: 1, exercise: squat, defaultSets: 4, defaultReps: 5, defaultWeight: 100.0)
        template.exercises.append(te1)
        template.exercises.append(te2)
        context.insert(template)
        try context.save()

        // Start workout from template (pass templateRepository so timesPerformed is updated)
        let autoFill = AutoFillService(workoutRepository: workoutRepo)
        let workoutVM = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepo,
            autoFillService: autoFill,
            templateRepository: templateRepo
        )
        await workoutVM.startWorkout()

        let workout = try #require(workoutVM.workout, "Workout should be created")
        #expect(workout.name == "Test Push Day")
        #expect(workout.exercises.count == 2, "Should have 2 exercises from template")
        #expect(workout.completedAt == nil, "Workout should not be finished yet")

        // Verify sets were created
        let sortedExercises = workout.exercises.sorted(by: { $0.order < $1.order })
        #expect(sortedExercises[0].sets.count == 3, "Bench should have 3 sets")
        #expect(sortedExercises[1].sets.count == 4, "Squat should have 4 sets")

        // Auto-fill should have populated bench press weight from prior history
        let firstBenchSet = sortedExercises[0].sets.first
        #expect(firstBenchSet?.weight == 80.0, "Auto-fill should use prior 80kg bench press")

        // Log and complete all sets
        for we in workout.exercises {
            for set in we.sets {
                workoutVM.completeSet(set)
            }
        }
        #expect(workoutVM.totalSetsCompleted == 7, "Should have completed 7 total sets (3+4)")

        // Finish the workout
        await workoutVM.finishWorkout()
        #expect(workoutVM.isFinished == true)
        #expect(workout.completedAt != nil, "Workout should have a completion timestamp")

        // Verify the workout is persisted in history
        let savedWorkouts = try await workoutRepo.fetchAll()
        let savedWorkout = savedWorkouts.first(where: { $0.id == workout.id })
        #expect(savedWorkout != nil, "Finished workout should appear in history")
        #expect(savedWorkout?.completedAt != nil)
        #expect(savedWorkout?.exercises.count == 2)

        // Template stats should have updated
        let savedTemplates = try await templateRepo.fetchAll()
        let savedTemplate = savedTemplates.first(where: { $0.id == template.id })
        #expect(savedTemplate?.timesPerformed == 1, "Template timesPerformed should increment to 1")

        // Deterministically wait for the fire-and-forget saveDraft Task
        // spawned by completeSet() / addExercise() / finishWorkout(). This
        // replaces the old `for _ in 0..<20 { await Task.yield() }` dance
        // which was flaky on slower machines.
        await workoutVM.awaitPendingSave()
    }

    // MARK: - Test 3: Exercise Browse → fuzzySearch → Coach Suggests Weight
    //
    // This test uses ONLY mock repositories (no SwiftData writes) so it cannot be
    // killed by concurrent BackingData.reset crashes from unrelated test suites.

    @Test("Exercise browse and coach weight suggestion via real repository and mock service")
    func exerciseBrowseAndCoachSuggestsWeight() async throws {
        // Build inline exercise list (same names that exercises.json contains)
        let inlineExercises: [Exercise] = [
            TestFixtures.makeExercise(name: "Barbell Squat", equipment: "barbell", externalId: "inline_0"),
            TestFixtures.makeExercise(name: "Barbell Deadlift", equipment: "barbell", externalId: "inline_1"),
            TestFixtures.makeExercise(name: "Barbell Bench Press - Medium Grip", equipment: "barbell", externalId: "inline_2"),
            TestFixtures.makeExercise(name: "Barbell Curl", equipment: "barbell", externalId: "inline_3"),
            TestFixtures.makeExercise(name: "Bent Over Barbell Row", equipment: "barbell", externalId: "inline_4"),
            TestFixtures.makeExercise(name: "Dumbbell Shoulder Press", equipment: "dumbbell", externalId: "inline_5"),
            TestFixtures.makeExercise(name: "Barbell Shoulder Press", equipment: "barbell", externalId: "inline_6"),
            TestFixtures.makeExercise(name: "Barbell Incline Bench Press - Medium Grip", equipment: "barbell", externalId: "inline_7"),
        ]

        // Step 1: Browse — verify mock repo correctly filters on search query
        let mockExerciseRepo = MockExerciseRepository()
        mockExerciseRepo.exercises = inlineExercises

        let libraryVM = ExerciseLibraryViewModel(exerciseRepository: mockExerciseRepo)
        libraryVM.searchQuery = "Barbell Bench Press"
        await libraryVM.performSearch()
        #expect(!libraryVM.exercises.isEmpty, "Search for 'Barbell Bench Press' should return results")
        let foundBench = libraryVM.exercises.first(where: {
            $0.name.lowercased().contains("bench") && $0.name.lowercased().contains("press")
        })
        #expect(foundBench != nil, "Should find bench press in search results")

        // Step 2: Verify MockExerciseRepository.fuzzySearch handles Claude-style exercise names
        let fuzzyResults = try await mockExerciseRepo.fuzzySearch(query: "Barbell Bench Press - Medium Grip")
        #expect(!fuzzyResults.isEmpty, "fuzzySearch should find bench press")
        #expect(
            fuzzyResults.contains(where: { $0.name == "Barbell Bench Press - Medium Grip" }),
            "fuzzySearch should find exact name match"
        )

        // Step 3: Coach suggests weight — tool call to suggest_weight with no prior history
        // (MockWorkoutRepository returns empty recentSets → "Start with a moderate weight")
        let mockWorkoutRepo = MockWorkoutRepository()
        let mockTemplateRepo = MockTemplateRepository()
        let mockPrefRepo = MockTrainingPreferenceRepository()

        let mock = MockAnthropicService()
        mock.stubbedEventSequences = [
            // Call 1: Claude calls suggest_weight
            [
                .toolUse(id: "sw1", name: "suggest_weight", inputJSON: """
                {"exercise_name": "Barbell Bench Press - Medium Grip"}
                """),
                .complete
            ],
            // Call 2: Claude responds after seeing tool result
            [
                .text("Start with a moderate weight and adjust based on feel."),
                .complete
            ]
        ]

        let chatVM = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: mockExerciseRepo,
            workoutRepository: mockWorkoutRepo,
            templateRepository: mockTemplateRepo,
            preferenceRepository: mockPrefRepo
        )

        await chatVM.sendMessage("What weight should I use for bench press?")

        // Verify: 2 API calls made (tool call + follow-up response)
        #expect(mock.streamChatCallCount == 2, "Should have made 2 API calls: tool + response")

        // Verify: tool result message exists in chat history
        let toolResultMessages = chatVM.messages.filter {
            if case .toolResult = $0.content { return true }
            return false
        }
        #expect(!toolResultMessages.isEmpty, "Tool result should be in chat history")

        // Verify: the tool executed and returned SOME response (exercise found or not)
        let toolResultContent = toolResultMessages.compactMap { msg -> String? in
            if case .toolResult(_, let content) = msg.content { return content }
            return nil
        }.first ?? ""
        #expect(!toolResultContent.isEmpty, "Tool result content should not be empty: got '\(toolResultContent)'")

        // The tool should not return an error (exercise is in the mock dataset)
        #expect(!toolResultContent.hasPrefix("Error:"), "Tool should find the exercise: \(toolResultContent)")
    }

    // MARK: - Test 4: Coach Creates Multi-Day Program → All Templates Visible

    @Test("Coach creates 3-day program, all templates saved and visible on home screen")
    func coachCreatesMultiDayProgramAllTemplatesVisible() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let loadedReal = try await importRealExercises(into: context)
        if !loadedReal {
            insertInlineExercises(into: context)
        }

        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        // Mock: Claude creates a 3-day PPL program using real exercise names
        let mock = MockAnthropicService()
        mock.stubbedEventSequences = [
            // Call 1: Claude creates a program
            [
                .text("I'll build you a Push/Pull/Legs program."),
                .toolUse(id: "prog1", name: "create_program", inputJSON: """
                {
                    "program_name": "PPL Program",
                    "templates": [
                        {
                            "template_name": "Push Day",
                            "exercises": [
                                {"name": "Barbell Bench Press - Medium Grip", "sets": 4, "reps": 8},
                                {"name": "Barbell Shoulder Press", "sets": 3, "reps": 10},
                                {"name": "Barbell Curl", "sets": 3, "reps": 12}
                            ]
                        },
                        {
                            "template_name": "Pull Day",
                            "exercises": [
                                {"name": "Barbell Deadlift", "sets": 4, "reps": 5},
                                {"name": "Bent Over Barbell Row", "sets": 4, "reps": 8}
                            ]
                        },
                        {
                            "template_name": "Leg Day",
                            "exercises": [
                                {"name": "Barbell Squat", "sets": 4, "reps": 6},
                                {"name": "Barbell Deadlift", "sets": 3, "reps": 8}
                            ]
                        }
                    ]
                }
                """),
                .complete
            ],
            // Call 2: Claude confirms
            [
                .text("Your PPL Program is ready with 3 templates. Tap save to confirm."),
                .complete
            ]
        ]

        let chatVM = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            preferenceRepository: prefRepo
        )

        await chatVM.sendMessage("Create a 3-day push pull legs program")

        // Templates should be auto-saved directly (no confirmation step needed)
        let allTemplates = try await templateRepo.fetchAll()
        #expect(allTemplates.count == 3, "Should have saved 3 templates, found \(allTemplates.count)")

        let templateNames = allTemplates.map { $0.name }
        #expect(templateNames.contains("Push Day"), "Push Day should be saved")
        #expect(templateNames.contains("Pull Day"), "Pull Day should be saved")
        #expect(templateNames.contains("Leg Day"), "Leg Day should be saved")

        // Each template should have exercises
        for template in allTemplates {
            #expect(
                template.exercises.count > 0,
                "\(template.name) should have at least one matched exercise"
            )
        }

        // HomeViewModel with the SAME repository should see all 3 templates
        let homeVM = HomeViewModel(templateRepository: templateRepo, workoutRepository: workoutRepo)
        await homeVM.loadTemplates()
        #expect(homeVM.templates.count == 3, "Home should show all 3 templates")
        #expect(homeVM.templates.contains(where: { $0.name == "Push Day" }), "Home should show Push Day")
        #expect(homeVM.templates.contains(where: { $0.name == "Pull Day" }), "Home should show Pull Day")
        #expect(homeVM.templates.contains(where: { $0.name == "Leg Day" }), "Home should show Leg Day")
    }
}
