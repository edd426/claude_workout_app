import Foundation

// MARK: - ProxiedAnthropicService
//
// Routes Claude chat through the Azure Function proxy endpoint (/api/chat)
// instead of calling the Anthropic API directly. This keeps the API key
// server-side (Phase 2 requirement).

final class ProxiedAnthropicService: AnthropicServiceProtocol, @unchecked Sendable {

    private let networkService: any NetworkServiceProtocol

    init(networkService: any NetworkServiceProtocol) {
        self.networkService = networkService
    }

    func streamChat(
        messages: [ChatMessage],
        systemPrompt: String,
        tools: [ToolDefinition]?,
        model: String,
        thinkingBudget: Int?
    ) -> AsyncThrowingStream<StreamingEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let maxTokens = thinkingBudget.map { max(4096, $0 + 4096) } ?? 4096
                    let body = ProxyChatRequest(
                        model: model,
                        system: systemPrompt,
                        messages: messages.compactMap { ProxyChatRequest.ProxyMessage($0) },
                        tools: tools?.map { ProxyChatRequest.ProxyTool($0) },
                        maxTokens: maxTokens,
                        stream: true,
                        thinkingBudget: thinkingBudget
                    )

                    var lineBuffer = ""
                    var toolUseId: String?
                    var toolUseName: String?
                    var toolInputAccumulator = ""

                    for try await chunk in networkService.streamPost(endpoint: "/api/chat", body: body) {
                        guard let text = String(data: chunk, encoding: .utf8) else { continue }
                        lineBuffer += text

                        // Process complete lines from the buffer
                        while let newlineRange = lineBuffer.range(of: "\n") {
                            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
                            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            guard trimmed.hasPrefix("data: ") else { continue }
                            let jsonStr = String(trimmed.dropFirst(6))
                            guard jsonStr != "[DONE]" else { continue }

                            guard let jsonData = jsonStr.data(using: .utf8),
                                  let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                            else { continue }

                            let eventType = event["type"] as? String

                            switch eventType {
                            case "content_block_start":
                                if let block = event["content_block"] as? [String: Any],
                                   let blockType = block["type"] as? String,
                                   blockType == "tool_use" {
                                    toolUseId = block["id"] as? String
                                    toolUseName = block["name"] as? String
                                    toolInputAccumulator = ""
                                }

                            case "content_block_delta":
                                if let delta = event["delta"] as? [String: Any] {
                                    let deltaType = delta["type"] as? String
                                    if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String {
                                        continuation.yield(.thinking(thinking))
                                    } else if deltaType == "text_delta", let text = delta["text"] as? String {
                                        continuation.yield(.text(text))
                                    } else if deltaType == "input_json_delta",
                                              let partial = delta["partial_json"] as? String {
                                        toolInputAccumulator += partial
                                    }
                                }

                            case "content_block_stop":
                                if let id = toolUseId, let name = toolUseName {
                                    continuation.yield(.toolUse(id: id, name: name, inputJSON: toolInputAccumulator))
                                    toolUseId = nil
                                    toolUseName = nil
                                    toolInputAccumulator = ""
                                }

                            case "message_stop":
                                continuation.yield(.complete)

                            default:
                                break
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Request body types (Anthropic API format)

private struct ProxyChatRequest: Encodable, Sendable {
    let model: String
    let system: String
    let messages: [ProxyMessage]
    let tools: [ProxyTool]?
    let maxTokens: Int
    let stream: Bool
    let thinkingBudget: Int?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools, stream
        case maxTokens = "max_tokens"
        case thinkingBudget = "thinking_budget"
    }

    // MARK: - ProxyMessage

    struct ProxyMessage: Encodable, Sendable {
        let role: String
        let content: ProxyContent

        enum ProxyContent: Encodable, Sendable {
            case text(String)
            case blocks([ProxyContentBlock])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let str):
                    try container.encode(str)
                case .blocks(let arr):
                    try container.encode(arr)
                }
            }
        }

        struct ProxyContentBlock: Encodable, Sendable {
            let type: String
            // For text blocks
            var text: String?
            // For tool_use blocks
            var id: String?
            var name: String?
            var input: JSONValue?
            // For tool_result blocks
            var toolUseId: String?

            enum CodingKeys: String, CodingKey {
                case type, text, id, name, input
                case toolUseId = "tool_use_id"
            }
        }

        init?(_ message: ChatMessage) {
            switch message.content {
            case .text(let str):
                switch message.role {
                case .user:
                    self.role = "user"
                    self.content = .text(str)
                case .assistant:
                    self.role = "assistant"
                    self.content = .text(str)
                case .system:
                    return nil // system goes in top-level system field
                }

            case .toolUse(let id, let name, let inputJSON):
                self.role = "assistant"
                // Parse JSON input
                let inputValue: JSONValue
                if let data = inputJSON.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    inputValue = .object(dict.mapValues { JSONValue.fromAny($0) })
                } else {
                    inputValue = .object([:])
                }
                self.content = .blocks([
                    ProxyContentBlock(type: "tool_use", text: nil, id: id, name: name, input: inputValue, toolUseId: nil)
                ])

            case .toolResult(let toolUseId, let resultContent):
                self.role = "user"
                self.content = .blocks([
                    ProxyContentBlock(type: "tool_result", text: resultContent, id: nil, name: nil, input: nil, toolUseId: toolUseId)
                ])
            }
        }
    }

    struct ProxyTool: Encodable, Sendable {
        let name: String
        let description: String
        let inputSchema: [String: JSONValue]

        enum CodingKeys: String, CodingKey {
            case name, description
            case inputSchema = "input_schema"
        }

        init(_ definition: ToolDefinition) {
            self.name = definition.name
            self.description = definition.description
            // Re-parse the stored JSON string back into a codable dict
            if let data = definition.inputSchemaJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.inputSchema = dict.mapValues { JSONValue.fromAny($0) }
            } else {
                self.inputSchema = ["type": .string("object")]
            }
        }
    }
}

// MARK: - JSONValue: a Codable heterogeneous JSON value

/// Used to encode arbitrary JSON schemas in Codable types.
private enum JSONValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    static func fromAny(_ value: Any) -> JSONValue {
        switch value {
        case let v as String: return .string(v)
        case let v as Int: return .int(v)
        case let v as Double: return .double(v)
        case let v as Bool: return .bool(v)
        case let v as [Any]: return .array(v.map { fromAny($0) })
        case let v as [String: Any]: return .object(v.mapValues { fromAny($0) })
        default: return .null
        }
    }
}
