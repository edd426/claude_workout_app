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
        // Return container so callers can keep it alive for the duration of the test
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

        #expect(vm.messages.contains { $0.role == .user && $0.content == "How many sets should I do?" })
        withExtendedLifetime(container) {}
    }

    @Test("Sending a message yields assistant response")
    func sendMessageYieldsAssistantResponse() async throws {
        let (vm, _, container) = try makeViewModel(events: [.text("Do 3 sets of 8."), .complete])
        await vm.sendMessage("How many sets?")

        let assistantMsgs = vm.messages.filter { $0.role == .assistant }
        #expect(assistantMsgs.count == 1)
        #expect(assistantMsgs.first?.content == "Do 3 sets of 8.")
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

    // MARK: - Tool Use

    @Test("Tool use event triggers tool execution and sends follow-up")
    func toolUseTriggersExecution() async throws {
        let (vm, mock, container) = try makeViewModel(events: [
            .toolUse(id: "t1", name: "get_recent_workouts", inputJSON: "{}"),
            .complete,
            .text("You have 3 recent workouts."),
            .complete
        ])

        await vm.sendMessage("Show my workouts")

        // Should have called streamChat twice (first response + follow-up after tool)
        #expect(mock.streamChatCallCount == 2)
        withExtendedLifetime(container) {}
    }

    @Test("Text chunks are accumulated during streaming")
    func textChunksAccumulated() async throws {
        let (vm, _, container) = try makeViewModel(events: [.text("Hello"), .text(" world"), .complete])
        // Note: streaming text is cleared after completion
        await vm.sendMessage("Hi")

        let assistantMsgs = vm.messages.filter { $0.role == .assistant }
        #expect(assistantMsgs.first?.content == "Hello world")
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
}
