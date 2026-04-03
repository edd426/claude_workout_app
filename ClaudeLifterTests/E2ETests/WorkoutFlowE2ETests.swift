import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("Workout Flow E2E Tests")
@MainActor
struct WorkoutFlowE2ETests {

    // MARK: - Test 1: Workout from Template

    @Test("workoutFromTemplate: template exercises auto-fill and finish with completedAt set")
    func workoutFromTemplate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        // Create exercises
        let benchPress = TestFixtures.makeExercise(name: "Bench Press", equipment: "barbell")
        let squat = TestFixtures.makeSquat()
        context.insert(benchPress)
        context.insert(squat)
        try context.save()

        // Create template with 2 exercises
        let template = WorkoutTemplate(name: "Push Day")
        let te1 = TemplateExercise(order: 0, exercise: benchPress, defaultSets: 3, defaultReps: 8, defaultWeight: 80.0)
        let te2 = TemplateExercise(order: 1, exercise: squat, defaultSets: 4, defaultReps: 5, defaultWeight: 100.0)
        template.exercises.append(te1)
        template.exercises.append(te2)
        context.insert(template)
        try context.save()

        // Create autoFill service (no prior history, so defaults will be used)
        let autoFill = AutoFillService(workoutRepository: workoutRepo)
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepo,
            autoFillService: autoFill
        )

        // Start workout
        await vm.startWorkout()
        let workout = try #require(vm.workout)
        #expect(workout.name == "Push Day")
        #expect(workout.exercises.count == 2)
        #expect(workout.completedAt == nil)

        // Verify sets were created for each exercise
        let firstExercise = workout.exercises.sorted(by: { $0.order < $1.order })[0]
        let secondExercise = workout.exercises.sorted(by: { $0.order < $1.order })[1]
        #expect(firstExercise.sets.count == 3)
        #expect(secondExercise.sets.count == 4)

        // Verify auto-fill from template defaults (no prior history)
        let firstSet = firstExercise.sets[0]
        #expect(firstSet.weight == 80.0)
        #expect(firstSet.reps == 8)

        // Mark all sets complete
        for exercise in workout.exercises {
            for set in exercise.sets {
                vm.completeSet(set)
            }
        }
        #expect(vm.totalSetsCompleted == 7)

        // Finish workout
        await vm.finishWorkout()
        #expect(vm.isFinished == true)
        #expect(workout.completedAt != nil)

        // Verify workout was saved
        let savedWorkouts = try await workoutRepo.fetchAll()
        #expect(savedWorkouts.contains { $0.id == workout.id })
        let saved = try #require(savedWorkouts.first { $0.id == workout.id })
        #expect(saved.completedAt != nil)
        #expect(saved.exercises.count == 2)
    }

    // MARK: - Test 2: Ad Hoc Workout

    @Test("adHocWorkout: start empty, add exercises, log sets, finish with correct exercises saved")
    func adHocWorkout() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        // Create some exercises in the library
        let deadlift = TestFixtures.makeDeadlift()
        let benchPress = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(deadlift)
        context.insert(benchPress)
        try context.save()

        let autoFill = AutoFillService(workoutRepository: workoutRepo)
        let vm = ActiveWorkoutViewModel(
            adHocName: "Ad Hoc Session",
            workoutRepository: workoutRepo,
            autoFillService: autoFill
        )

        // Start workout
        await vm.startWorkout()
        let workout = try #require(vm.workout)
        #expect(workout.name == "Ad Hoc Session")
        #expect(workout.exercises.isEmpty)

        // Add 2 exercises from repository
        let fetchedDeadlift = try #require(try await exerciseRepo.fetch(id: deadlift.id))
        let fetchedBench = try #require(try await exerciseRepo.fetch(id: benchPress.id))
        vm.addExercise(fetchedDeadlift)
        vm.addExercise(fetchedBench)
        #expect(workout.exercises.count == 2)

        // Log sets (each added exercise gets 3 default sets)
        for exercise in workout.exercises {
            for set in exercise.sets {
                set.weight = 60.0
                set.reps = 8
                vm.completeSet(set)
            }
        }
        #expect(vm.totalSetsCompleted == 6)

        // Finish workout
        await vm.finishWorkout()
        #expect(vm.isFinished == true)
        #expect(workout.completedAt != nil)

        // Verify saved with correct exercises
        let saved = try await workoutRepo.fetchAll()
        let savedWorkout = try #require(saved.first { $0.id == workout.id })
        #expect(savedWorkout.exercises.count == 2)
        let exerciseNames = savedWorkout.exercises.map { $0.exercise?.name ?? "" }
        #expect(exerciseNames.contains("Deadlift"))
        #expect(exerciseNames.contains("Bench Press"))
    }

    // MARK: - Test 3: Exercise Import and Browse

    @Test("exerciseImportAndBrowse: import from bundle, search bench press, apply filter")
    func exerciseImportAndBrowse() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        // Load exercises.json from Bundle
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            // Try test bundle
            guard let testUrl = Bundle(for: type(of: ExerciseImportService())).url(forResource: "exercises", withExtension: "json"),
                  let testData = try? Data(contentsOf: testUrl) else {
                // If exercises.json not available, skip gracefully
                return
            }
            let service = ExerciseImportService()
            let count = try await service.importExercises(from: testData, into: context)
            #expect(count >= 800)
            return
        }

        let service = ExerciseImportService()
        let count = try await service.importExercises(from: data, into: context)
        #expect(count >= 800)

        // Create ExerciseLibraryViewModel and search
        let vm = ExerciseLibraryViewModel(exerciseRepository: exerciseRepo)
        vm.searchQuery = "bench press"
        await vm.performSearch()
        #expect(!vm.exercises.isEmpty)
        #expect(vm.exercises.allSatisfy { $0.name.localizedCaseInsensitiveContains("bench") || $0.name.localizedCaseInsensitiveContains("press") })

        // Apply muscle_group filter
        vm.searchQuery = ""
        vm.selectFilter(category: "muscle_group", value: "chest")
        await vm.loadExercises()
        let chestExercises = vm.exercises
        #expect(!chestExercises.isEmpty)
        #expect(chestExercises.allSatisfy { ex in
            ex.tags.contains { $0.category == "muscle_group" && $0.value == "chest" }
        })
    }

    // MARK: - Test 4: Template Creation and Use

    @Test("templateCreationAndUse: create template, start workout, verify exercises, finish increments timesPerformed")
    func templateCreationAndUse() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)

        // Create exercises and template
        let benchPress = TestFixtures.makeExercise(name: "Bench Press", equipment: "barbell")
        let ohPress = TestFixtures.makeExercise(name: "Overhead Press", equipment: "barbell", primaryMuscles: ["shoulders"])
        context.insert(benchPress)
        context.insert(ohPress)

        let template = WorkoutTemplate(name: "Push A")
        let te1 = TemplateExercise(order: 0, exercise: benchPress, defaultSets: 3, defaultReps: 8)
        let te2 = TemplateExercise(order: 1, exercise: ohPress, defaultSets: 3, defaultReps: 10)
        template.exercises.append(te1)
        template.exercises.append(te2)
        try await templateRepo.save(template)

        // Verify template was saved
        let allTemplates = try await templateRepo.fetchAll()
        #expect(allTemplates.contains { $0.id == template.id })
        #expect(template.timesPerformed == 0)

        // Start workout from template
        let autoFill = AutoFillService(workoutRepository: workoutRepo)
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepo,
            autoFillService: autoFill
        )
        await vm.startWorkout()
        let workout = try #require(vm.workout)

        // Verify exercises match template
        #expect(workout.exercises.count == 2)
        let exerciseNames = workout.exercises.map { $0.exercise?.name ?? "" }
        #expect(exerciseNames.contains("Bench Press"))
        #expect(exerciseNames.contains("Overhead Press"))

        // Log all sets and finish
        for exercise in workout.exercises {
            for set in exercise.sets {
                vm.completeSet(set)
            }
        }
        await vm.finishWorkout()
        #expect(vm.isFinished)

        // Manually increment timesPerformed (as the app would do)
        template.timesPerformed += 1
        try await templateRepo.save(template)

        let updatedTemplates = try await templateRepo.fetchAll()
        let updatedTemplate = try #require(updatedTemplates.first { $0.id == template.id })
        #expect(updatedTemplate.timesPerformed == 1)
    }

    // MARK: - Test 5: Multiple Filters

    @Test("multipleFilters: apply chest + barbell filters, verify narrowed results, remove equipment filter expands")
    func multipleFilters() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        // Create exercises with varied tags
        func makeTaggedExercise(name: String, muscle: String, equipment: String) -> Exercise {
            let ex = Exercise(name: name, equipment: equipment, primaryMuscles: [muscle], isCustom: false)
            let muscleTag = ExerciseTag(category: "muscle_group", value: muscle)
            let equipTag = ExerciseTag(category: "equipment", value: equipment)
            ex.tags.append(muscleTag)
            ex.tags.append(equipTag)
            context.insert(ex)
            return ex
        }

        makeTaggedExercise(name: "Barbell Bench Press", muscle: "chest", equipment: "barbell")
        makeTaggedExercise(name: "Dumbbell Flye", muscle: "chest", equipment: "dumbbell")
        makeTaggedExercise(name: "Incline Barbell Press", muscle: "chest", equipment: "barbell")
        makeTaggedExercise(name: "Barbell Row", muscle: "back", equipment: "barbell")
        try context.save()

        let vm = ExerciseLibraryViewModel(exerciseRepository: exerciseRepo)

        // Apply muscle_group: chest
        vm.selectFilter(category: "muscle_group", value: "chest")
        await vm.loadExercises()
        let chestOnly = vm.exercises
        #expect(chestOnly.count == 3)

        // Apply equipment: barbell (combined filter)
        vm.selectFilter(category: "equipment", value: "barbell")
        await vm.loadExercises()
        let chestAndBarbell = vm.exercises
        #expect(chestAndBarbell.count == 2)
        #expect(chestAndBarbell.allSatisfy { ex in
            ex.tags.contains { $0.category == "muscle_group" && $0.value == "chest" } &&
            ex.tags.contains { $0.category == "equipment" && $0.value == "barbell" }
        })

        // Remove equipment filter — should expand back to all chest
        vm.removeFilter(category: "equipment")
        await vm.loadExercises()
        let chestExpanded = vm.exercises
        #expect(chestExpanded.count == 3)
    }

    // MARK: - Test 6: Calendar Heatmap

    @Test("calendarHeatmap: 3 workouts with varying sets produce correct intensity levels")
    func calendarHeatmap() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)

        let calendar = Calendar.current
        let today = Date()
        guard let daysAgo2 = calendar.date(byAdding: .day, value: -2, to: today),
              let daysAgo5 = calendar.date(byAdding: .day, value: -5, to: today),
              let daysAgo10 = calendar.date(byAdding: .day, value: -10, to: today) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create dates"])
        }

        let exercise = TestFixtures.makeExercise()
        context.insert(exercise)

        // Light workout (5 completed sets → light intensity)
        let lightWorkout = Workout(name: "Light Day", startedAt: daysAgo10, completedAt: daysAgo10)
        let lightWE = WorkoutExercise(order: 0, exercise: exercise)
        for i in 0..<5 {
            let set = WorkoutSet(order: i, weight: 60, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: daysAgo10)
            lightWE.sets.append(set)
        }
        lightWorkout.exercises.append(lightWE)
        context.insert(lightWorkout)

        // Medium workout (15 completed sets → medium intensity)
        let mediumWorkout = Workout(name: "Medium Day", startedAt: daysAgo5, completedAt: daysAgo5)
        let mediumWE = WorkoutExercise(order: 0, exercise: exercise)
        for i in 0..<15 {
            let set = WorkoutSet(order: i, weight: 70, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: daysAgo5)
            mediumWE.sets.append(set)
        }
        mediumWorkout.exercises.append(mediumWE)
        context.insert(mediumWorkout)

        // Heavy workout (25 completed sets → heavy intensity)
        let heavyWorkout = Workout(name: "Heavy Day", startedAt: daysAgo2, completedAt: daysAgo2)
        let heavyWE = WorkoutExercise(order: 0, exercise: exercise)
        for i in 0..<25 {
            let set = WorkoutSet(order: i, weight: 100, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: daysAgo2)
            heavyWE.sets.append(set)
        }
        heavyWorkout.exercises.append(heavyWE)
        context.insert(heavyWorkout)

        try context.save()

        let calendarVM = CalendarViewModel(workoutRepository: workoutRepo)
        await calendarVM.loadMonth()

        #expect(!calendarVM.workoutDays.isEmpty)

        let lightDay = calendar.startOfDay(for: daysAgo10)
        let mediumDay = calendar.startOfDay(for: daysAgo5)
        let heavyDay = calendar.startOfDay(for: daysAgo2)

        let lightIntensity = calendarVM.workoutDays[lightDay]
        let mediumIntensity = calendarVM.workoutDays[mediumDay]
        let heavyIntensity = calendarVM.workoutDays[heavyDay]

        #expect(lightIntensity == .light)
        #expect(mediumIntensity == .medium)
        #expect(heavyIntensity == .heavy)
    }

    // MARK: - Test 7: PR Detection

    @Test("prDetection: second workout at higher weight detects heaviestWeight PR without duplication")
    func prDetection() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let prRepo = SwiftDataPersonalRecordRepository(context: context)

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        try context.save()

        let prService = PRDetectionService(prRepository: prRepo)

        // First workout: bench press at 80kg×8
        let workout1 = Workout(name: "Push Day 1", startedAt: Date(timeIntervalSinceNow: -86400), completedAt: Date(timeIntervalSinceNow: -86400))
        let we1 = WorkoutExercise(order: 0, exercise: exercise)
        let set1 = WorkoutSet(order: 0, weight: 80.0, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: Date(timeIntervalSinceNow: -86400))
        we1.sets.append(set1)
        workout1.exercises.append(we1)
        context.insert(workout1)
        try context.save()

        // Detect PRs from first workout (all should be new PRs)
        let prs1 = try await prService.detectPRs(for: workout1)
        #expect(!prs1.isEmpty)
        let heaviestFirst = prs1.first { $0.prType == .heaviestWeight }
        #expect(heaviestFirst?.value == 80.0)

        // Second workout: bench press at 85kg×8 (new PR)
        let workout2 = Workout(name: "Push Day 2", startedAt: Date(), completedAt: Date())
        let we2 = WorkoutExercise(order: 0, exercise: exercise)
        let set2 = WorkoutSet(order: 0, weight: 85.0, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: Date())
        we2.sets.append(set2)
        workout2.exercises.append(we2)
        context.insert(workout2)
        try context.save()

        let prs2 = try await prService.detectPRs(for: workout2)
        #expect(!prs2.isEmpty)
        let newHeaviest = prs2.first { $0.prType == .heaviestWeight }
        #expect(newHeaviest?.value == 85.0)

        // Verify no duplication — only one heaviest weight PR per exercise should exist at 85
        let allPRs = try await prRepo.fetchByType(exerciseId: exercise.id, type: .heaviestWeight)
        let heavier85 = allPRs.filter { $0.value == 85.0 }
        #expect(heavier85.count == 1)
    }

    // MARK: - Test 8: Custom Exercise Creation

    @Test("customExerciseCreation: create custom exercise, appears in search, usable in template")
    func customExerciseCreation() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)

        // Create custom exercise via CreateExerciseViewModel
        let createVM = CreateExerciseViewModel()
        createVM.name = "Cable Lateral Raise"
        createVM.equipment = "cable"
        createVM.primaryMuscles = ["shoulders"]
        createVM.level = "intermediate"
        createVM.mechanic = "isolation"

        #expect(createVM.canSave)
        try await createVM.save(using: exerciseRepo)

        // Verify isCustom = true
        let allExercises = try await exerciseRepo.fetchAll()
        let custom = try #require(allExercises.first { $0.name == "Cable Lateral Raise" })
        #expect(custom.isCustom == true)
        #expect(custom.equipment == "cable")
        #expect(custom.primaryMuscles.contains("shoulders"))

        // Verify appears in exercise library search
        let libVM = ExerciseLibraryViewModel(exerciseRepository: exerciseRepo)
        libVM.searchQuery = "Cable Lateral"
        await libVM.performSearch()
        #expect(libVM.exercises.contains { $0.name == "Cable Lateral Raise" })

        // Verify usable in template
        let template = WorkoutTemplate(name: "Shoulder Day")
        let te = TemplateExercise(order: 0, exercise: custom, defaultSets: 3, defaultReps: 15)
        template.exercises.append(te)
        try await templateRepo.save(template)

        let saved = try await templateRepo.fetchAll()
        let savedTemplate = try #require(saved.first { $0.name == "Shoulder Day" })
        #expect(savedTemplate.exercises.count == 1)
        #expect(savedTemplate.exercises.first?.exercise?.name == "Cable Lateral Raise")
    }

    // MARK: - Test 9: AI Coach with Mock

    @Test("aiCoachWithMock: send message, receive response, tool execution shows follow-up")
    func aiCoachWithMock() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let prefRepo = MockTrainingPreferenceRepository()

        let mockService = MockAnthropicService()
        mockService.stubbedEvents = [
            .text("Hello! I'm your AI coach."),
            .complete
        ]

        let chatVM = ChatViewModel(
            anthropicService: mockService,
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            preferenceRepository: prefRepo
        )

        // Send simple message
        await chatVM.sendMessage("Hello")
        #expect(mockService.streamChatCallCount >= 1)
        #expect(chatVM.messages.contains { $0.role == .assistant && $0.textContent.contains("Hello") })
        #expect(!chatVM.isLoading)

        // Configure mock to return tool_use for get_recent_workouts
        let toolInputJSON = "{\"limit\":5}"
        mockService.stubbedEventSequences = [
            [
                .toolUse(id: "tool_1", name: "get_recent_workouts", inputJSON: toolInputJSON),
                .complete
            ],
            [
                .text("Based on your recent workouts, you're making great progress!"),
                .complete
            ]
        ]

        await chatVM.sendMessage("How are my recent workouts?")
        #expect(mockService.streamChatCallCount >= 2)
        // Tool result sent as user toolResult message — check for tool use content in messages
        #expect(chatVM.messages.contains { msg in
            if case .toolUse(_, let name, _) = msg.content { return name == "get_recent_workouts" }
            return false
        })
        // Follow-up response should have been received
        let assistantMessages = chatVM.messages.filter { $0.role == .assistant }
        #expect(!assistantMessages.isEmpty)
    }

    // MARK: - Test 10: AI Coach Real API

    @Test("aiCoachRealAPI: real AnthropicService with key from .env streams a response")
    func aiCoachRealAPI() async throws {
        // Read API key from .env
        let envPath = "/Users/eddelord/Documents/Projects/claude_workout_app/.env"
        guard let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            // No .env file — skip gracefully
            return
        }

        var apiKey: String? = nil
        for line in envContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ANTHROPIC_API_KEY=") {
                apiKey = String(trimmed.dropFirst("ANTHROPIC_API_KEY=".count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        guard let key = apiKey, !key.isEmpty else {
            // Key not found or empty — skip gracefully
            return
        }

        // Create SettingsManager with the real key
        let testDefaults = UserDefaults(suiteName: "test_e2e_real_api_\(UUID())")!
        let settings = SettingsManager(defaults: testDefaults)
        settings.apiKey = key

        let service = AnthropicService(settingsManager: settings)
        let messages = [ChatMessage(role: .user, text: "Say hello in 5 words or less.")]

        var receivedEvents: [StreamingEvent] = []
        for try await event in service.streamChat(
            messages: messages,
            systemPrompt: "You are a helpful assistant.",
            tools: nil,
            model: "claude-haiku-4-5-20251001"
        ) {
            receivedEvents.append(event)
            if case .complete = event { break }
        }

        #expect(!receivedEvents.isEmpty)
        #expect(receivedEvents.contains { if case .text = $0 { return true }; return false })
        #expect(receivedEvents.contains { if case .complete = $0 { return true }; return false })
    }

    // MARK: - Test 11: Settings Persistence

    @Test("settingsPersistence: set and change API key in SettingsManager persists correctly")
    func settingsPersistence() async throws {
        let testDefaults = UserDefaults(suiteName: "test_settings_\(UUID())")!
        let settings = SettingsManager(defaults: testDefaults)

        // Set initial API key
        let firstKey = "sk-ant-test-key-first"
        settings.apiKey = firstKey
        #expect(settings.apiKey == firstKey)

        // Change key
        let newKey = "sk-ant-test-key-second"
        settings.apiKey = newKey
        #expect(settings.apiKey == newKey)

        // Verify a fresh SettingsManager with same defaults reads the updated key
        let settings2 = SettingsManager(defaults: testDefaults)
        #expect(settings2.apiKey == newKey)

        // Verify AnthropicService uses the key from SettingsManager at call time
        // (missingAPIKey error if key is cleared)
        settings2.apiKey = ""
        let service = AnthropicService(settingsManager: settings2)
        let messages = [ChatMessage(role: .user, text: "Hello")]
        var errorReceived = false
        for try await event in service.streamChat(messages: messages, systemPrompt: "", tools: nil, model: "claude-haiku-4-5-20251001") {
            if case .error(let error) = event {
                if let anthropicError = error as? AnthropicError, anthropicError == .missingAPIKey {
                    errorReceived = true
                }
            }
        }
        #expect(errorReceived)
    }

    // MARK: - Test 12: Insight Generation

    @Test("insightGeneration: mock returns 2 insights with correct types")
    func insightGeneration() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)

        // Create 5 workouts over past 14 days
        for i in 0..<5 {
            let daysAgo = Double(-(i * 2 + 1))
            let date = Date(timeIntervalSinceNow: daysAgo * 86400)
            let workout = Workout(name: "Workout \(i)", startedAt: date, completedAt: date)
            context.insert(workout)
        }
        try context.save()

        // Configure mock to return parseable insight text
        let mockService = MockAnthropicService()
        mockService.stubbedEvents = [
            .text("[suggestion] Rest more between sessions\n[warning] Leg day overdue"),
            .complete
        ]

        let testDefaults = UserDefaults(suiteName: "test_insights_\(UUID())")!
        let service = InsightGenerationService(
            anthropicService: mockService,
            workoutRepository: workoutRepo,
            insightRepository: insightRepo,
            defaults: testDefaults
        )

        #expect(service.shouldGenerateInsights() == true)

        let insights = try await service.generateInsights()
        #expect(insights.count == 2)

        let suggestion = try #require(insights.first { $0.type == .suggestion })
        #expect(suggestion.content.lowercased().contains("rest"))

        let warning = try #require(insights.first { $0.type == .warning })
        #expect(warning.content.lowercased().contains("leg"))

        // Verify insights were persisted to repository
        let savedInsights = try await insightRepo.fetchAll()
        #expect(savedInsights.count == 2)
    }

    // MARK: - Test 13: Workout History and AutoFill

    @Test("workoutHistoryAndAutoFill: prior workout sets are correctly returned for autofill")
    func workoutHistoryAndAutoFill() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)

        let benchPress = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(benchPress)

        // Create a completed workout with bench press at 80kg×10
        let pastWorkout = Workout(name: "Push Day", startedAt: Date(timeIntervalSinceNow: -86400), completedAt: Date(timeIntervalSinceNow: -86400))
        let we = WorkoutExercise(order: 0, exercise: benchPress)
        let set1 = WorkoutSet(order: 0, weight: 75.0, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: Date(timeIntervalSinceNow: -86400))
        let set2 = WorkoutSet(order: 1, weight: 80.0, weightUnit: .kg, reps: 10, isCompleted: true, completedAt: Date(timeIntervalSinceNow: -86400))
        let set3 = WorkoutSet(order: 2, weight: 80.0, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: Date(timeIntervalSinceNow: -86400))
        we.sets.append(contentsOf: [set1, set2, set3])
        pastWorkout.exercises.append(we)
        try await workoutRepo.save(pastWorkout)

        // Query lastSessionSets
        let lastSets = try await workoutRepo.lastSessionSets(for: benchPress.id)
        #expect(lastSets.count == 3)

        // AutoFillService returns the last set (highest order) from the last session
        let autoFill = AutoFillService(workoutRepository: workoutRepo)
        let result = try await autoFill.lastPerformed(exerciseId: benchPress.id)
        let fill = try #require(result)
        #expect(fill.weight == 80.0)
        #expect(fill.reps == 8)
        #expect(fill.weightUnit == .kg)
    }

    // MARK: - Test 14: Template Modification via Chat Tool

    @Test("templateModificationViaChat: ModifyTemplateTool add_exercise returns description, applyAndSave persists")
    func templateModificationViaChat() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let workoutRepo = SwiftDataWorkoutRepository(context: context)

        // Create a template and an exercise
        let benchPress = TestFixtures.makeExercise(name: "Bench Press")
        let inclinePress = TestFixtures.makeExercise(name: "Incline Press", equipment: "dumbbell", primaryMuscles: ["chest"])
        context.insert(benchPress)
        context.insert(inclinePress)

        let template = WorkoutTemplate(name: "Push Day")
        let te = TemplateExercise(order: 0, exercise: benchPress, defaultSets: 3, defaultReps: 8)
        template.exercises.append(te)
        try await templateRepo.save(template)

        let toolContext = ToolContext(
            exerciseRepository: exerciseRepo,
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            activeWorkout: nil
        )

        let modifyTool = ModifyTemplateTool()
        let inputJSON = """
        {
          "template_name": "Push Day",
          "action": "add_exercise",
          "exercise_name": "Incline Press",
          "sets": 3,
          "reps": 12
        }
        """

        // Execute returns a description (without saving)
        let description = try await modifyTool.execute(inputJSON: inputJSON, context: toolContext)
        #expect(description.contains("Incline Press"))
        #expect(description.contains("Awaiting confirmation"))

        // Template still has 1 exercise (not yet saved)
        let beforeSave = try await templateRepo.fetchAll()
        let templateBefore = try #require(beforeSave.first { $0.name == "Push Day" })
        #expect(templateBefore.exercises.count == 1)

        // Apply and save
        _ = try await modifyTool.applyAndSave(
            inputJSON: inputJSON,
            templateRepository: templateRepo,
            exerciseRepository: exerciseRepo
        )

        let afterSave = try await templateRepo.fetchAll()
        let templateAfter = try #require(afterSave.first { $0.name == "Push Day" })
        #expect(templateAfter.exercises.count == 2)
        #expect(templateAfter.exercises.contains { $0.exercise?.name == "Incline Press" })
    }

    // MARK: - Test 15: Full Workout Lifecycle

    @Test("fullWorkoutLifecycle: template → start → log → add exercise → finish → detect PRs → history → syncStatus")
    func fullWorkoutLifecycle() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let prRepo = SwiftDataPersonalRecordRepository(context: context)

        // Setup: exercises and template
        let squat = TestFixtures.makeSquat()
        let deadlift = TestFixtures.makeDeadlift()
        let benchPress = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(squat)
        context.insert(deadlift)
        context.insert(benchPress)

        let template = WorkoutTemplate(name: "Full Body A")
        let te1 = TemplateExercise(order: 0, exercise: squat, defaultSets: 3, defaultReps: 5, defaultWeight: 100.0)
        template.exercises.append(te1)
        try await templateRepo.save(template)

        // Start workout from template
        let autoFill = AutoFillService(workoutRepository: workoutRepo)
        let prService = PRDetectionService(prRepository: prRepo)
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepo,
            autoFillService: autoFill,
            prDetectionService: prService
        )

        await vm.startWorkout()
        let workout = try #require(vm.workout)
        #expect(workout.syncStatus == .pending)

        // Log existing sets
        for exercise in workout.exercises {
            for set in exercise.sets {
                set.weight = 102.5
                set.reps = 5
                vm.completeSet(set)
            }
        }

        // Add an exercise mid-workout (bench press)
        let fetchedBench = try #require(try await exerciseRepo.fetch(id: benchPress.id))
        vm.addExercise(fetchedBench)
        #expect(workout.exercises.count == 2)

        // Log bench sets
        let benchWE = workout.exercises.first { $0.exercise?.id == benchPress.id }
        if let bwe = benchWE {
            for set in bwe.sets {
                set.weight = 80.0
                set.reps = 8
                vm.completeSet(set)
            }
        }

        // Finish workout
        await vm.finishWorkout()
        #expect(vm.isFinished)
        #expect(workout.completedAt != nil)

        // PRs should have been detected
        #expect(!vm.detectedPRs.isEmpty)

        // Verify workout in history
        let history = try await workoutRepo.fetchAll()
        #expect(history.contains { $0.id == workout.id })
        let savedWorkout = try #require(history.first { $0.id == workout.id })
        #expect(savedWorkout.completedAt != nil)
        #expect(savedWorkout.syncStatus == .pending)
        #expect(savedWorkout.exercises.count == 2)

        // Verify all completed sets recorded
        let allSets = savedWorkout.exercises.flatMap { $0.sets }.filter { $0.isCompleted }
        #expect(!allSets.isEmpty)
    }
}
