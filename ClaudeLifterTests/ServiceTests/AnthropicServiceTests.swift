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

        let msg = ChatMessage(role: .user, content: "Hi")
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

        let msg = ChatMessage(role: .user, content: "Hi")
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

        let msg = ChatMessage(role: .user, content: "Tell me about squats")
        let tool = ToolDefinition(name: "test_tool", description: "A test tool", inputSchema: ["type": "object"])

        for try await _ in mock.streamChat(messages: [msg], systemPrompt: "Be helpful", tools: [tool], model: "claude-sonnet-4-6") {}

        #expect(mock.streamChatCallCount == 1)
        #expect(mock.lastMessages.first?.content == "Tell me about squats")
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

    // MARK: - ChatMessage

    @Test("ChatMessage defaults to current timestamp")
    func chatMessageTimestamp() {
        let before = Date()
        let msg = ChatMessage(role: .user, content: "test")
        let after = Date()
        #expect(msg.timestamp >= before)
        #expect(msg.timestamp <= after)
    }

    @Test("ChatMessage identity is stable across equal content")
    func chatMessageIdentity() {
        let id = UUID()
        let m1 = ChatMessage(id: id, role: .user, content: "hello")
        let m2 = ChatMessage(id: id, role: .user, content: "hello")
        #expect(m1 == m2)
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
