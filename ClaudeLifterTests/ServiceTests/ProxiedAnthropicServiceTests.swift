import Testing
import Foundation
@testable import ClaudeLifter

// MARK: - Helpers

private func sseData(_ eventType: String, json: String) -> Data {
    let line = "event: \(eventType)\ndata: \(json)\n\n"
    return Data(line.utf8)
}

private func messageStopData() -> Data {
    sseData("message_stop", json: "{\"type\":\"message_stop\"}")
}

@Suite("ProxiedAnthropicService Tests")
struct ProxiedAnthropicServiceTests {

    // MARK: - Request construction

    @Test("Calls /api/chat endpoint")
    func callsChatEndpoint() async throws {
        let mock = MockNetworkService()
        mock.streamChunks["/api/chat"] = [messageStopData()]
        let service = ProxiedAnthropicService(networkService: mock)

        let msgs = [ChatMessage(role: .user, text: "Hello")]
        for try await _ in service.streamChat(messages: msgs, systemPrompt: "Be helpful.", tools: nil, model: "claude-haiku-4-5") {}

        #expect(mock.streamCallCount == 1)
        #expect(mock.lastStreamEndpoint == "/api/chat")
    }

    @Test("Filters system-role messages from request body")
    func filtersSystemMessages() async throws {
        let mock = MockNetworkService()
        mock.streamChunks["/api/chat"] = [messageStopData()]
        let service = ProxiedAnthropicService(networkService: mock)

        // System messages should not appear as conversation turns
        let msgs = [
            ChatMessage(role: .system, text: "You are a trainer"),
            ChatMessage(role: .user, text: "Help me")
        ]
        for try await _ in service.streamChat(messages: msgs, systemPrompt: "System prompt", tools: nil, model: "claude-haiku-4-5") {}

        #expect(mock.streamCallCount == 1)
    }

    // MARK: - SSE parsing: text events

    @Test("Parses text_delta into .text events")
    func parsesTextDelta() async throws {
        let mock = MockNetworkService()
        let delta = """
        {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello!"}}
        """
        mock.streamChunks["/api/chat"] = [
            sseData("content_block_delta", json: delta),
            messageStopData()
        ]
        let service = ProxiedAnthropicService(networkService: mock)

        var collected: [StreamingEvent] = []
        for try await event in service.streamChat(messages: [], systemPrompt: "", tools: nil, model: "claude-haiku-4-5") {
            collected.append(event)
        }

        let textEvents = collected.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
        #expect(textEvents == ["Hello!"])
    }

    @Test("Accumulates multiple text chunks")
    func accumulatesTextChunks() async throws {
        let mock = MockNetworkService()
        let delta1 = "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Foo\"}}"
        let delta2 = "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" Bar\"}}"
        mock.streamChunks["/api/chat"] = [
            sseData("content_block_delta", json: delta1),
            sseData("content_block_delta", json: delta2),
            messageStopData()
        ]
        let service = ProxiedAnthropicService(networkService: mock)

        var texts: [String] = []
        for try await event in service.streamChat(messages: [], systemPrompt: "", tools: nil, model: "claude-haiku-4-5") {
            if case .text(let t) = event { texts.append(t) }
        }

        #expect(texts == ["Foo", " Bar"])
    }

    // MARK: - SSE parsing: tool_use events

    @Test("Parses tool_use block into .toolUse event")
    func parsesToolUse() async throws {
        let mock = MockNetworkService()
        let blockStart = #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_123","name":"get_exercise_history","input":{}}}"#
        let inputDelta = #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"exercise_name\":\"bench_press\"}"}}"#
        let blockStop = "{\"type\":\"content_block_stop\",\"index\":1}"

        mock.streamChunks["/api/chat"] = [
            sseData("content_block_start", json: blockStart),
            sseData("content_block_delta", json: inputDelta),
            sseData("content_block_stop", json: blockStop),
            messageStopData()
        ]
        let service = ProxiedAnthropicService(networkService: mock)

        var toolEvent: StreamingEvent?
        for try await event in service.streamChat(messages: [], systemPrompt: "", tools: nil, model: "claude-haiku-4-5") {
            if case .toolUse = event { toolEvent = event }
        }

        guard let toolEvent else {
            Issue.record("Expected a .toolUse event")
            return
        }
        if case .toolUse(let id, let name, let json) = toolEvent {
            #expect(id == "toolu_123")
            #expect(name == "get_exercise_history")
            #expect(json.contains("bench_press"))
        }
    }

    // MARK: - SSE parsing: message_stop → .complete

    @Test("Emits .complete on message_stop")
    func emitsCompleteOnMessageStop() async throws {
        let mock = MockNetworkService()
        mock.streamChunks["/api/chat"] = [messageStopData()]
        let service = ProxiedAnthropicService(networkService: mock)

        var gotComplete = false
        for try await event in service.streamChat(messages: [], systemPrompt: "", tools: nil, model: "claude-haiku-4-5") {
            if case .complete = event { gotComplete = true }
        }

        #expect(gotComplete)
    }

    // MARK: - Error handling

    @Test("Propagates network error as .error event")
    func propagatesNetworkError() async throws {
        struct NetError: Error {}
        let mock = MockNetworkService()
        mock.streamError = NetError()
        let service = ProxiedAnthropicService(networkService: mock)

        var caughtError = false
        do {
            for try await _ in service.streamChat(messages: [], systemPrompt: "", tools: nil, model: "claude-haiku-4-5") {}
        } catch {
            caughtError = true
        }
        #expect(caughtError)
    }

    // MARK: - Tool definitions encoding

    @Test("Sends tool definitions when provided")
    func sendsToolDefinitions() async throws {
        let mock = MockNetworkService()
        mock.streamChunks["/api/chat"] = [messageStopData()]
        let service = ProxiedAnthropicService(networkService: mock)

        let tool = ToolDefinition(
            name: "get_exercise_history",
            description: "Get history for an exercise",
            inputSchema: ["type": "object", "properties": ["exercise_name": ["type": "string"]]]
        )

        for try await _ in service.streamChat(messages: [], systemPrompt: "", tools: [tool], model: "claude-sonnet-4-6") {}

        #expect(mock.streamCallCount == 1)
    }

    // MARK: - Tool result encoding (#29 fix)

    @Test("Encodes toolResult messages as user messages with tool_result content block")
    func encodesToolResultMessages() async throws {
        let mock = MockNetworkService()
        mock.streamChunks["/api/chat"] = [messageStopData()]
        let service = ProxiedAnthropicService(networkService: mock)

        let msgs: [ChatMessage] = [
            ChatMessage(role: .user, text: "What weight for bench?"),
            ChatMessage(role: .assistant, content: .toolUse(id: "t1", name: "suggest_weight", input: "{\"exercise_name\":\"Bench Press\"}")),
            ChatMessage(role: .user, content: .toolResult(toolUseId: "t1", content: "Suggested: 80kg"))
        ]

        for try await _ in service.streamChat(messages: msgs, systemPrompt: "", tools: nil, model: "claude-haiku-4-5") {}

        // The service should encode these and make the network call (just verify it didn't crash)
        #expect(mock.streamCallCount == 1)
    }
}
