import Foundation


// MARK: - Message Content

enum MessageContent: Sendable, Equatable {
    /// Plain text content
    case text(String)
    /// An assistant tool-use block (Claude calling a tool)
    case toolUse(id: String, name: String, input: String)
    /// A tool result sent back to Claude
    case toolResult(toolUseId: String, content: String)
}

// MARK: - Chat Message (our domain type, not SDK type)

struct ChatMessage: Sendable, Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: MessageContent
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: MessageContent, timestamp: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    /// Convenience init for plain text messages (the common case)
    init(id: UUID = UUID(), role: MessageRole, text: String, timestamp: Date = .now) {
        self.id = id
        self.role = role
        self.content = .text(text)
        self.timestamp = timestamp
    }

    /// Returns the text string if content is `.text(_)`, otherwise a human-readable description
    var textContent: String {
        switch content {
        case .text(let str):
            return str
        case .toolUse(_, let name, _):
            return "[Tool: \(name)]"
        case .toolResult(_, let result):
            return result
        }
    }
}

// MARK: - Tool Definition (our domain type)

struct ToolDefinition: Sendable {
    let name: String
    let description: String
    /// JSON Schema encoded as a JSON string for Sendable compliance
    let inputSchemaJSON: String

    init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        if let data = try? JSONSerialization.data(withJSONObject: inputSchema),
           let str = String(data: data, encoding: .utf8) {
            self.inputSchemaJSON = str
        } else {
            self.inputSchemaJSON = "{\"type\":\"object\"}"
        }
    }
}

// MARK: - Streaming Events

enum StreamingEvent: Sendable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, inputJSON: String)
    case complete
    case error(Error)
}

// MARK: - Protocol

protocol AnthropicServiceProtocol: Sendable {
    func streamChat(
        messages: [ChatMessage],
        systemPrompt: String,
        tools: [ToolDefinition]?,
        model: String,
        thinkingBudget: Int?
    ) -> AsyncThrowingStream<StreamingEvent, Error>
}

// MARK: - Default Extension (backward compatibility)

extension AnthropicServiceProtocol {
    func streamChat(
        messages: [ChatMessage],
        systemPrompt: String,
        tools: [ToolDefinition]?,
        model: String
    ) -> AsyncThrowingStream<StreamingEvent, Error> {
        streamChat(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            model: model,
            thinkingBudget: nil
        )
    }
}
