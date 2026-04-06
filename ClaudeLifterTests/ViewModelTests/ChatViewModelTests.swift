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

    // MARK: - Auto-Save (replaces confirmation flow)

    @Test("create_template tool auto-saves the template directly")
    func createTemplateToolAutoSaves() async throws {
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
            [.text("I've created a Push Day template for you."), .complete]
        ]

        let templateRepo = SwiftDataTemplateRepository(context: context)
        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: templateRepo,
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context)
        )

        await vm.sendMessage("Create a push day template")

        // Template should be saved directly without confirmation
        let saved = try await templateRepo.fetchAll()
        #expect(saved.contains { $0.name == "Push Day" })
        withExtendedLifetime(container) {}
    }

    @Test("create_template with no matched exercises does NOT save a template")
    func createTemplateWithNoMatchesDoesNotSave() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        // No exercises inserted — nothing will match

        let mock = MockAnthropicService()
        mock.stubbedEventSequences = [
            [
                .toolUse(id: "t1", name: "create_template", inputJSON: """
                {"template_name": "Ghost Day", "exercises": [{"name": "Unknown Exercise XYZ", "sets": 3, "reps": 8}]}
                """),
                .complete
            ],
            [.text("I could not find matching exercises."), .complete]
        ]

        let templateRepo = SwiftDataTemplateRepository(context: context)
        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: templateRepo,
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context)
        )

        await vm.sendMessage("Create a push day template")

        // No template should be saved when 0 exercises matched
        let saved = try await templateRepo.fetchAll()
        #expect(saved.isEmpty)
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

    // MARK: - Issue #56: Chat History Persistence

    @Test("Sending a message persists it to chatRepository")
    func sendMessagePersistsToChatRepository() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockChat = MockChatMessageRepository()

        let mock = MockAnthropicService()
        mock.stubbedEvents = [.text("Reply"), .complete]

        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            chatRepository: mockChat
        )

        await vm.sendMessage("Hello coach")

        // User message + assistant message should be persisted
        let saved = mockChat.messages
        let userMessages = saved.filter { $0.role == .user }
        let assistantMessages = saved.filter { $0.role == .assistant }
        #expect(userMessages.count == 1)
        #expect(userMessages.first?.content == "Hello coach")
        #expect(assistantMessages.count == 1)
        #expect(assistantMessages.first?.content == "Reply")
        withExtendedLifetime(container) {}
    }

    @Test("loadHistory populates messages from repository")
    func loadHistoryPopulatesMessages() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockChat = MockChatMessageRepository()

        let mock = MockAnthropicService()
        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            chatRepository: mockChat
        )

        // Pre-populate repository with saved messages matching the VM's conversationId
        let convoId = vm.currentConversationId
        let msg1 = AIChatMessage(role: .user, content: "Previous question", conversationId: convoId)
        let msg2 = AIChatMessage(role: .assistant, content: "Previous answer", conversationId: convoId)
        mockChat.messages = [msg1, msg2]

        await vm.loadHistory()

        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].textContent == "Previous question")
        #expect(vm.messages[1].role == .assistant)
        #expect(vm.messages[1].textContent == "Previous answer")
        withExtendedLifetime(container) {}
    }

    @Test("clearChat deletes messages from repository")
    func clearChatDeletesFromRepository() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockChat = MockChatMessageRepository()

        // Pre-populate repository
        mockChat.messages = [
            AIChatMessage(role: .user, content: "Old message"),
            AIChatMessage(role: .assistant, content: "Old reply")
        ]

        let mock = MockAnthropicService()
        mock.stubbedEvents = [.text("Hi"), .complete]

        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            chatRepository: mockChat
        )

        vm.clearChat()

        // Wait briefly for the background Task to execute
        try await Task.sleep(for: .milliseconds(50))

        let remaining = try await mockChat.fetch(workoutId: nil)
        #expect(remaining.isEmpty)
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

    // MARK: - Conversation Management

    @Test("startNewConversation generates new ID and clears messages")
    func startNewConversationClearsState() async throws {
        let (vm, _, container) = try makeViewModel(events: [.text("Hi"), .complete])
        await vm.sendMessage("Hello")
        let oldConvoId = vm.currentConversationId

        vm.startNewConversation()

        #expect(vm.messages.isEmpty)
        #expect(vm.currentConversationId != oldConvoId)
        #expect(vm.currentStreamingText == "")
        withExtendedLifetime(container) {}
    }

    @Test("Persisted messages include conversationId")
    func persistedMessagesIncludeConversationId() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockChat = MockChatMessageRepository()

        let mock = MockAnthropicService()
        mock.stubbedEvents = [.text("Reply"), .complete]

        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            chatRepository: mockChat
        )

        await vm.sendMessage("Hello")

        // Wait for background Task persistence
        try await Task.sleep(for: .milliseconds(50))

        let saved = mockChat.messages
        #expect(!saved.isEmpty)
        for msg in saved {
            #expect(msg.conversationId == vm.currentConversationId)
        }
        withExtendedLifetime(container) {}
    }

    @Test("loadConversation loads messages for a specific conversation")
    func loadConversationLoadsSpecificMessages() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockChat = MockChatMessageRepository()

        let convoA = UUID()
        let convoB = UUID()
        mockChat.messages = [
            AIChatMessage(role: .user, content: "Message A", conversationId: convoA),
            AIChatMessage(role: .user, content: "Message B", conversationId: convoB)
        ]

        let mock = MockAnthropicService()
        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            chatRepository: mockChat
        )

        await vm.loadConversation(id: convoA)

        #expect(vm.messages.count == 1)
        #expect(vm.messages.first?.textContent == "Message A")
        #expect(vm.currentConversationId == convoA)
        withExtendedLifetime(container) {}
    }

    @Test("listConversations returns grouped conversations sorted by date")
    func listConversationsReturnsGrouped() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockChat = MockChatMessageRepository()

        let convoA = UUID()
        let convoB = UUID()
        let olderDate = Date.now.addingTimeInterval(-3600)
        let newerDate = Date.now

        mockChat.messages = [
            AIChatMessage(role: .user, content: "Old question", conversationId: convoA, timestamp: olderDate),
            AIChatMessage(role: .user, content: "New question", conversationId: convoB, timestamp: newerDate)
        ]

        let mock = MockAnthropicService()
        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            chatRepository: mockChat
        )

        let convos = await vm.listConversations()

        #expect(convos.count == 2)
        // Most recent first
        #expect(convos.first?.preview == "New question")
        withExtendedLifetime(container) {}
    }

    // MARK: - Memory Bounds (#71 fix)

    @Test("Messages are trimmed after tool chain completes")
    func messagesAreTrimmedAfterToolChain() async throws {
        let (vm, mock, container) = try makeViewModel()

        // Pre-populate messages array with >100 entries to simulate a long session
        for i in 0..<120 {
            let role: MessageRole = i.isMultiple(of: 2) ? .user : .assistant
            vm.messages.append(ChatMessage(role: role, text: "Message \(i)"))
        }
        #expect(vm.messages.count == 120)

        // Now trigger a tool chain that completes with a final text response
        mock.stubbedEventSequences = [
            [.toolUse(id: "t1", name: "get_recent_workouts", inputJSON: "{}"), .complete],
            [.text("Here are your workouts."), .complete]
        ]

        await vm.sendMessage("Show workouts")

        // After tool chain completes, messages should be trimmed to <= 100
        #expect(vm.messages.count <= 100)
        // The most recent messages should be preserved (including the final assistant response)
        let lastMsg = vm.messages.last
        #expect(lastMsg?.role == .assistant)
        #expect(lastMsg?.textContent == "Here are your workouts.")
        withExtendedLifetime(container) {}
    }

    @Test("listConversations limits results to recent conversations")
    func listConversationsLimitsResults() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockChat = MockChatMessageRepository()

        // Create 60 conversations, some older than 30 days
        for i in 0..<60 {
            let convoId = UUID()
            let daysAgo = Double(i) // 0 days ago, 1 day ago, ... 59 days ago
            let date = Date.now.addingTimeInterval(-daysAgo * 86400)
            mockChat.messages.append(
                AIChatMessage(role: .user, content: "Question \(i)", conversationId: convoId, timestamp: date)
            )
        }

        let mock = MockAnthropicService()
        let vm = ChatViewModel(
            anthropicService: mock,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            chatRepository: mockChat
        )

        let convos = await vm.listConversations()

        // Should not return all 60 — should be bounded (e.g., last 30 days or max 50)
        #expect(convos.count <= 50)
        withExtendedLifetime(container) {}
    }
}
