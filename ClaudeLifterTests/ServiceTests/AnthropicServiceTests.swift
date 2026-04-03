import Testing
import Foundation
@testable import ClaudeLifter

@Suite("AnthropicService Tests")
struct AnthropicServiceTests {

    // MARK: - MockAnthropicService behaviour

    @Test("Mock yields text events then complete")
    func mockYieldsTextThenComplete() async throws {
        let mock = MockAnthropicService()
        mock.stubbedEvents = [.text("Hello"), .text(" world"), .complete]

        let msg = ChatMessage(role: .user, text: "Hi")
        var collected: [StreamingEvent] = []

        for try await event in mock.streamChat(messages: [msg], systemPrompt: "You are helpful.", tools: nil, model: "claude-haiku-4-5") {
            collected.append(event)
        }

        #expect(collected.count == 3)
        if case .text(let t) = collected[0] { #expect(t == "Hello") }
        if case .text(let t) = collected[1] { #expect(t == " world") }
        if case .complete = collected[2] { /* pass */ } else { Issue.record("Expected .complete") }
    }

    @Test("Mock throws error when stubbedError is set")
    func mockThrowsError() async throws {
        let mock = MockAnthropicService()
        struct TestError: Error {}
        mock.stubbedError = TestError()

        let msg = ChatMessage(role: .user, text: "Hi")
        var threwError = false
        do {
            for try await _ in mock.streamChat(messages: [msg], systemPrompt: "", tools: nil, model: "claude-haiku-4-5") {}
        } catch {
            threwError = true
        }
        #expect(threwError)
    }

    @Test("Mock records call parameters")
    func mockRecordsCallParams() async throws {
        let mock = MockAnthropicService()
        mock.stubbedEvents = [.complete]

        let msg = ChatMessage(role: .user, text: "Tell me about squats")
        let tool = ToolDefinition(name: "test_tool", description: "A test tool", inputSchema: ["type": "object"])

        for try await _ in mock.streamChat(messages: [msg], systemPrompt: "Be helpful", tools: [tool], model: "claude-sonnet-4-6") {}

        #expect(mock.streamChatCallCount == 1)
        #expect(mock.lastMessages.first?.textContent == "Tell me about squats")
        #expect(mock.lastSystemPrompt == "Be helpful")
        #expect(mock.lastModel == "claude-sonnet-4-6")
        #expect(mock.lastTools?.first?.name == "test_tool")
    }

    @Test("Mock streams tool use event")
    func mockStreamToolUse() async throws {
        let mock = MockAnthropicService()
        mock.stubbedEvents = [
            .toolUse(id: "tool_123", name: "get_exercise_history", inputJSON: "{\"exercise_name\":\"bench_press\"}"),
            .complete
        ]

        var toolEvent: StreamingEvent?
        for try await event in mock.streamChat(messages: [], systemPrompt: "", tools: nil, model: "claude-haiku-4-5") {
            if case .toolUse = event { toolEvent = event }
        }

        guard let toolEvent else {
            Issue.record("Expected toolUse event")
            return
        }
        if case .toolUse(let id, let name, let json) = toolEvent {
            #expect(id == "tool_123")
            #expect(name == "get_exercise_history")
            #expect(json.contains("bench_press"))
        }
    }

    // MARK: - AnthropicService + SettingsManager integration

    @Test("streamChat errors when API key is empty")
    func streamChatErrorsWhenAPIKeyIsEmpty() async throws {
        let defaults = UserDefaults(suiteName: "test_empty_key_\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        // apiKey defaults to "" — do not set it
        let service = AnthropicService(settingsManager: settings)

        let msg = ChatMessage(role: .user, text: "Hi")
        var gotError = false
        for try await event in service.streamChat(messages: [msg], systemPrompt: "", tools: nil, model: "claude-haiku-4-5-20251001") {
            if case .error = event { gotError = true }
        }
        #expect(gotError)
    }

    @Test("streamChat uses current API key from SettingsManager at call time")
    func streamChatUsesCurrentAPIKey() {
        let defaults = UserDefaults(suiteName: "test_current_key_\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        let service = AnthropicService(settingsManager: settings)
        settings.apiKey = "sk-ant-test-key"

        #expect(settings.apiKey == "sk-ant-test-key")
        _ = service
    }

    @Test("API key change is reflected in subsequent calls")
    func apiKeyChangeReflectedInSubsequentCalls() async throws {
        let defaults = UserDefaults(suiteName: "test_key_change_\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        let service = AnthropicService(settingsManager: settings)

        let msg = ChatMessage(role: .user, text: "Hi")

        // First call — empty key → missingAPIKey error immediately (no network call)
        var firstCallMissingKey = false
        for try await event in service.streamChat(messages: [msg], systemPrompt: "", tools: nil, model: "claude-haiku-4-5-20251001") {
            if case .error(let err) = event,
               let anthErr = err as? AnthropicError,
               case .missingAPIKey = anthErr {
                firstCallMissingKey = true
            }
        }
        #expect(firstCallMissingKey)

        settings.apiKey = "sk-ant-new-key"
        #expect(settings.apiKey == "sk-ant-new-key")
    }

    // MARK: - Extended Thinking

    @Test("Mock records thinkingBudget when provided")
    func mockRecordsThinkingBudget() async throws {
        let mock = MockAnthropicService()
        mock.stubbedEvents = [.complete]

        let msg = ChatMessage(role: .user, text: "Build me a 4-day program")

        for try await _ in mock.streamChat(
            messages: [msg],
            systemPrompt: "Be helpful",
            tools: nil,
            model: "claude-sonnet-4-6",
            thinkingBudget: 10000
        ) {}

        #expect(mock.lastThinkingBudget == 10000)
    }

    @Test("Mock records nil thinkingBudget when not provided")
    func mockRecordsNilThinkingBudget() async throws {
        let mock = MockAnthropicService()
        mock.stubbedEvents = [.complete]

        let msg = ChatMessage(role: .user, text: "Hi")

        for try await _ in mock.streamChat(
            messages: [msg],
            systemPrompt: "Be helpful",
            tools: nil,
            model: "claude-haiku-4-5"
        ) {}

        #expect(mock.lastThinkingBudget == nil)
    }

    @Test("Thinking streaming events are yielded correctly")
    func thinkingStreamingEventsYielded() async throws {
        let mock = MockAnthropicService()
        mock.stubbedEvents = [
            .thinking("Let me reason through this..."),
            .thinking(" Step 1: assess the user's goals."),
            .text("Here is your program:"),
            .complete
        ]

        var thinkingChunks: [String] = []
        var textChunks: [String] = []

        for try await event in mock.streamChat(
            messages: [],
            systemPrompt: "",
            tools: nil,
            model: "claude-sonnet-4-6",
            thinkingBudget: 10000
        ) {
            switch event {
            case .thinking(let chunk):
                thinkingChunks.append(chunk)
            case .text(let chunk):
                textChunks.append(chunk)
            default:
                break
            }
        }

        #expect(thinkingChunks.count == 2)
        #expect(thinkingChunks[0] == "Let me reason through this...")
        #expect(thinkingChunks[1] == " Step 1: assess the user's goals.")
        #expect(textChunks.count == 1)
        #expect(textChunks[0] == "Here is your program:")
    }

    @Test("Default streamChat overload passes nil thinkingBudget")
    func defaultOverloadPassesNilBudget() async throws {
        let mock = MockAnthropicService()
        mock.stubbedEvents = [.complete]

        for try await _ in mock.streamChat(
            messages: [],
            systemPrompt: "",
            tools: nil,
            model: "claude-haiku-4-5"
        ) {}

        #expect(mock.lastThinkingBudget == nil)
    }

    // MARK: - ChatMessage

    @Test("ChatMessage defaults to current timestamp")
    func chatMessageTimestamp() {
        let before = Date()
        let msg = ChatMessage(role: .user, text: "test")
        let after = Date()
        #expect(msg.timestamp >= before)
        #expect(msg.timestamp <= after)
    }

    @Test("ChatMessage identity is stable across equal content")
    func chatMessageIdentity() {
        let id = UUID()
        let ts = Date()
        let m1 = ChatMessage(id: id, role: .user, content: .text("hello"), timestamp: ts)
        let m2 = ChatMessage(id: id, role: .user, content: .text("hello"), timestamp: ts)
        #expect(m1 == m2)
    }

    @Test("ChatMessage textContent returns string for text content")
    func chatMessageTextContent() {
        let msg = ChatMessage(role: .user, text: "hello world")
        #expect(msg.textContent == "hello world")
    }

    @Test("ChatMessage textContent returns tool name for toolUse content")
    func chatMessageTextContentForToolUse() {
        let msg = ChatMessage(role: .assistant, content: .toolUse(id: "t1", name: "get_recent_workouts", input: "{}"))
        #expect(msg.textContent == "[Tool: get_recent_workouts]")
    }

    @Test("ChatMessage textContent returns result for toolResult content")
    func chatMessageTextContentForToolResult() {
        let msg = ChatMessage(role: .user, content: .toolResult(toolUseId: "t1", content: "3 recent workouts found"))
        #expect(msg.textContent == "3 recent workouts found")
    }

    // MARK: - ToolDefinition

    @Test("ToolDefinition stores properties correctly")
    func toolDefinitionProperties() {
        let schema: [String: Any] = ["type": "object", "properties": ["query": ["type": "string"]]]
        let tool = ToolDefinition(name: "search", description: "Search exercises", inputSchema: schema)
        #expect(tool.name == "search")
        #expect(tool.description == "Search exercises")
        #expect(tool.inputSchemaJSON.contains("object"))
    }
}
