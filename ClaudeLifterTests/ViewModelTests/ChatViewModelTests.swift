import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("ChatViewModel Tests")
@MainActor
struct ChatViewModelTests {

    // MARK: - Helpers

    func makeViewModel(
        events: [StreamingEvent] = [.text("Hello!"), .complete]
    ) throws -> (ChatViewModel, MockAnthropicService, ModelContainer) {
        let container = try makeTestContainer()
        let context = container.mainContext

        let mock = MockAnthropicService()
        mock.stubbedEvents = events

        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context)
        )
        return (vm, mock, container)
    }

    // MARK: - Initial State

    @Test("Initial state is empty and not loading")
    func initialState() throws {
        let (vm, _, container) = try makeViewModel()
        #expect(vm.messages.isEmpty)
        #expect(!vm.isLoading)
        #expect(vm.errorMessage == nil)
        #expect(vm.currentStreamingText == "")
        withExtendedLifetime(container) {}
    }

    // MARK: - sendMessage

    @Test("Sending a message appends user message")
    func sendMessageAppendsUserMsg() async throws {
        let (vm, _, container) = try makeViewModel()
        await vm.sendMessage("How many sets should I do?")

        #expect(vm.messages.contains { $0.role == .user && $0.textContent == "How many sets should I do?" })
        withExtendedLifetime(container) {}
    }

    @Test("Sending a message yields assistant response")
    func sendMessageYieldsAssistantResponse() async throws {
        let (vm, _, container) = try makeViewModel(events: [.text("Do 3 sets of 8."), .complete])
        await vm.sendMessage("How many sets?")

        let assistantMsgs = vm.messages.filter { $0.role == .assistant }
        #expect(assistantMsgs.count == 1)
        #expect(assistantMsgs.first?.textContent == "Do 3 sets of 8.")
        withExtendedLifetime(container) {}
    }

    @Test("Sending a message clears streaming text after completion")
    func sendMessageClearsStreamingText() async throws {
        let (vm, _, container) = try makeViewModel(events: [.text("Hello!"), .complete])
        await vm.sendMessage("Hi")
        #expect(vm.currentStreamingText == "")
        #expect(!vm.isLoading)
        withExtendedLifetime(container) {}
    }

    @Test("Empty message is not sent")
    func emptyMessageNotSent() async throws {
        let (vm, mock, container) = try makeViewModel()
        await vm.sendMessage("   ")
        #expect(vm.messages.isEmpty)
        #expect(mock.streamChatCallCount == 0)
        withExtendedLifetime(container) {}
    }

    @Test("Error sets errorMessage property")
    func errorSetsErrorMessage() async throws {
        let (vm, mock, container) = try makeViewModel()
        struct ChatError: Error, LocalizedError {
            var errorDescription: String? { "Network error" }
        }
        mock.stubbedError = ChatError()

        await vm.sendMessage("Hello")
        #expect(vm.errorMessage == "Network error")
        #expect(!vm.isLoading)
        withExtendedLifetime(container) {}
    }

    // MARK: - API Key error handling

    @Test("Error message shown when API key missing")
    func errorMessageShownWhenAPIKeyMissing() async throws {
        let (vm, mock, container) = try makeViewModel()
        struct MissingKeyError: LocalizedError {
            var errorDescription: String? { "API key is missing. Please add your Anthropic API key in Settings." }
        }
        mock.stubbedError = MissingKeyError()

        await vm.sendMessage("Hello")
        #expect(vm.errorMessage?.lowercased().contains("api key") == true)
        #expect(!vm.isLoading)
        withExtendedLifetime(container) {}
    }

    @Test("Error message cleared on next successful send")
    func errorMessageClearedOnNextSuccessfulSend() async throws {
        let (vm, mock, container) = try makeViewModel()
        struct MissingKeyError: LocalizedError {
            var errorDescription: String? { "API key is missing. Please add your Anthropic API key in Settings." }
        }
        mock.stubbedError = MissingKeyError()
        await vm.sendMessage("Hello")
        #expect(vm.errorMessage != nil)

        mock.stubbedError = nil
        mock.stubbedEvents = [.text("All good!"), .complete]
        await vm.sendMessage("Try again")
        #expect(vm.errorMessage == nil)
        withExtendedLifetime(container) {}
    }

    // MARK: - clearChat

    @Test("clearChat resets all state")
    func clearChatResetsState() async throws {
        let (vm, _, container) = try makeViewModel(events: [.text("Hi"), .complete])
        await vm.sendMessage("Hello")

        vm.clearChat()

        #expect(vm.messages.isEmpty)
        #expect(vm.currentStreamingText == "")
        #expect(vm.errorMessage == nil)
        #expect(!vm.isLoading)
        withExtendedLifetime(container) {}
    }

    // MARK: - Tool Use (#29 fix: tool results correctly sent to Claude)

    @Test("Tool use event triggers tool execution and sends follow-up")
    func toolUseTriggersExecution() async throws {
        let (vm, mock, container) = try makeViewModel()
        mock.stubbedEventSequences = [
            [.toolUse(id: "t1", name: "get_recent_workouts", inputJSON: "{}"), .complete],
            [.text("You have 3 recent workouts."), .complete]
        ]

        await vm.sendMessage("Show my workouts")

        #expect(mock.streamChatCallCount == 2)
        withExtendedLifetime(container) {}
    }

    @Test("Tool results are sent as user messages with tool_result content — not system messages")
    func toolResultsSentAsUserMessages() async throws {
        let (vm, mock, container) = try makeViewModel()
        mock.stubbedEventSequences = [
            [.toolUse(id: "tool-123", name: "get_recent_workouts", inputJSON: "{}"), .complete],
            [.text("Here are your workouts."), .complete]
        ]

        await vm.sendMessage("Show my recent workouts")

        let secondCallMessages = mock.lastMessages
        let toolResultMsg = secondCallMessages.first { msg in
            if case .toolResult(_, _) = msg.content { return true }
            return false
        }
        #expect(toolResultMsg != nil)
        #expect(toolResultMsg?.role == .user)
        withExtendedLifetime(container) {}
    }

    @Test("Tool use messages include assistant tool_use content block in follow-up call")
    func toolUseMessagesIncludeAssistantBlock() async throws {
        let (vm, mock, container) = try makeViewModel()
        mock.stubbedEventSequences = [
            [.toolUse(id: "tool-abc", name: "get_recent_workouts", inputJSON: "{\"limit\": 5}"), .complete],
            [.text("You did 5 workouts."), .complete]
        ]

        await vm.sendMessage("Show workouts")

        let secondCallMessages = mock.lastMessages
        let assistantToolUseMsg = secondCallMessages.first { msg in
            if case .toolUse(_, _, _) = msg.content { return true }
            return false
        }
        #expect(assistantToolUseMsg != nil)
        #expect(assistantToolUseMsg?.role == .assistant)
        withExtendedLifetime(container) {}
    }

    @Test("No system-role messages appear in messages sent to API")
    func noSystemMessagesInAPICall() async throws {
        let (vm, mock, container) = try makeViewModel()
        mock.stubbedEventSequences = [
            [.toolUse(id: "t1", name: "get_recent_workouts", inputJSON: "{}"), .complete],
            [.text("Done."), .complete]
        ]

        await vm.sendMessage("Hello")

        let hasSystemMsg = mock.lastMessages.contains { $0.role == .system }
        #expect(!hasSystemMsg)
        withExtendedLifetime(container) {}
    }

    // MARK: - Chained Tool Use (#30 fix)

    @Test("Chained tool use: second tool call in follow-up is also handled")
    func chainedToolUseIsHandled() async throws {
        let (vm, mock, container) = try makeViewModel()
        mock.stubbedEventSequences = [
            [.toolUse(id: "t1", name: "get_recent_workouts", inputJSON: "{}"), .complete],
            [.toolUse(id: "t2", name: "suggest_weight", inputJSON: "{\"exercise_name\": \"Bench Press\"}"), .complete],
            [.text("Based on your history, try 80kg."), .complete]
        ]

        await vm.sendMessage("What weight should I use for bench?")

        #expect(mock.streamChatCallCount == 3)
        let assistantMsgs = vm.messages.filter { $0.role == .assistant }
        #expect(assistantMsgs.contains { $0.textContent == "Based on your history, try 80kg." })
        withExtendedLifetime(container) {}
    }

    @Test("Tool chain stops at max depth of 5 to prevent infinite loops")
    func toolChainStopsAtMaxDepth() async throws {
        let (vm, mock, container) = try makeViewModel()
        let toolCallEvent: [StreamingEvent] = [.toolUse(id: "t1", name: "get_recent_workouts", inputJSON: "{}"), .complete]
        mock.stubbedEventSequences = Array(repeating: toolCallEvent, count: 10)

        await vm.sendMessage("Test depth limit")

        #expect(mock.streamChatCallCount <= 6)
        withExtendedLifetime(container) {}
    }

    // MARK: - Text chunks

    @Test("Text chunks are accumulated during streaming")
    func textChunksAccumulated() async throws {
        let (vm, _, container) = try makeViewModel(events: [.text("Hello"), .text(" world"), .complete])
        await vm.sendMessage("Hi")

        let assistantMsgs = vm.messages.filter { $0.role == .assistant }
        #expect(assistantMsgs.first?.textContent == "Hello world")
        withExtendedLifetime(container) {}
    }

    // MARK: - Active Workout Context

    @Test("Setting activeWorkout updates activeWorkoutContext")
    func activeWorkoutUpdatesContext() throws {
        let workoutContainer = try makeTestContainer()
        let workoutContext = workoutContainer.mainContext
        let workout = Workout(name: "Push Day", startedAt: .now)
        workoutContext.insert(workout)

        let (vm, _, vmContainer) = try makeViewModel()
        vm.activeWorkout = workout
        #expect(vm.activeWorkoutContext == "Push Day")
        withExtendedLifetime(workoutContainer) {}
        withExtendedLifetime(vmContainer) {}
    }

    @Test("Clearing activeWorkout clears context")
    func clearingActiveWorkoutClearsContext() throws {
        let workoutContainer = try makeTestContainer()
        let workoutContext = workoutContainer.mainContext
        let workout = Workout(name: "Leg Day", startedAt: .now)
        workoutContext.insert(workout)

        let (vm, _, vmContainer) = try makeViewModel()
        vm.activeWorkout = workout
        vm.activeWorkout = nil
        #expect(vm.activeWorkoutContext == nil)
        withExtendedLifetime(workoutContainer) {}
        withExtendedLifetime(vmContainer) {}
    }

    // MARK: - Confirmation Flow

    @Test("create_template tool triggers confirmation flow")
    func createTemplateToolTriggersPendingConfirmation() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let bench = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(bench)
        try context.save()

        let mock = MockAnthropicService()
        mock.stubbedEventSequences = [
            [
                .toolUse(id: "t1", name: "create_template", inputJSON: """
                {"template_name": "Push Day", "exercises": [{"name": "Bench Press", "sets": 3, "reps": 8}]}
                """),
                .complete
            ],
            [.text("I've prepared a template for your review."), .complete]
        ]

        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context)
        )

        await vm.sendMessage("Create a push day template")

        #expect(vm.pendingConfirmation != nil)
        #expect(vm.pendingConfirmation?.toolName == "create_template")
        withExtendedLifetime(container) {}
    }

    @Test("Confirming pending action saves the template")
    func confirmPendingActionSavesTemplate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let bench = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(bench)
        try context.save()

        let mock = MockAnthropicService()
        mock.stubbedEventSequences = [
            [
                .toolUse(id: "t1", name: "create_template", inputJSON: """
                {"template_name": "My Template", "exercises": [{"name": "Bench Press", "sets": 3, "reps": 8}]}
                """),
                .complete
            ],
            [.text("Template ready."), .complete]
        ]

        let templateRepo = SwiftDataTemplateRepository(context: context)
        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: templateRepo,
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context)
        )

        await vm.sendMessage("Create a template")
        #expect(vm.pendingConfirmation != nil)

        await vm.confirmPendingAction()

        let saved = try await templateRepo.fetchAll()
        #expect(saved.contains { $0.name == "My Template" })
        #expect(vm.pendingConfirmation == nil)
        withExtendedLifetime(container) {}
    }

    @Test("Canceling pending action does not save template")
    func cancelPendingActionDoesNotSave() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let bench = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(bench)
        try context.save()

        let mock = MockAnthropicService()
        mock.stubbedEventSequences = [
            [
                .toolUse(id: "t1", name: "create_template", inputJSON: """
                {"template_name": "Cancelled Template", "exercises": [{"name": "Bench Press", "sets": 3, "reps": 8}]}
                """),
                .complete
            ],
            [.text("Template ready."), .complete]
        ]

        let templateRepo = SwiftDataTemplateRepository(context: context)
        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: templateRepo,
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context)
        )

        await vm.sendMessage("Create a template")
        #expect(vm.pendingConfirmation != nil)

        vm.cancelPendingAction()

        let saved = try await templateRepo.fetchAll()
        #expect(saved.isEmpty)
        #expect(vm.pendingConfirmation == nil)
        withExtendedLifetime(container) {}
    }

    // MARK: - System Prompt

    @Test("System prompt includes training preferences")
    func systemPromptIncludesPreferences() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)
        try await prefRepo.upsert(key: "training_style", value: "hypertrophy", source: "user_stated")

        let mock = MockAnthropicService()
        mock.stubbedEvents = [.text("Got it"), .complete]

        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: prefRepo
        )

        await vm.loadPreferences()
        await vm.sendMessage("Hello")

        #expect(mock.lastSystemPrompt.contains("training_style"))
        #expect(mock.lastSystemPrompt.contains("hypertrophy"))
        withExtendedLifetime(container) {}
    }

    // MARK: - Model Selection (#45 fix: use SettingsManager)

    @Test("ChatViewModel uses SettingsManager for model selection")
    func chatViewModelUsesSettingsManagerForModel() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let defaults = UserDefaults(suiteName: "test-model-\(UUID())")!
        let settings = SettingsManager(defaults: defaults)
        settings.aiModel = .sonnet

        let mock = MockAnthropicService()
        mock.stubbedEvents = [.text("Hi"), .complete]

        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            settings: settings
        )

        await vm.sendMessage("Hello")

        #expect(mock.lastModel == AIModel.sonnet.rawValue)
        withExtendedLifetime(container) {}
    }
}
