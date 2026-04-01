import Foundation
@preconcurrency import SwiftAnthropic

// MARK: - AnthropicError

enum AnthropicError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is missing. Please add your Anthropic API key in Settings."
        }
    }
}

// MARK: - AnthropicService

final class AnthropicService: AnthropicServiceProtocol, @unchecked Sendable {

    private let sdkService: (any SwiftAnthropic.AnthropicService)?
    private let settingsManager: SettingsManager?

    /// Production init — reads API key from SettingsManager at call time so that
    /// keys entered after app launch are always picked up.
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        self.sdkService = nil
    }

    // Internal init for testing with a custom SDK service
    init(sdkService: any SwiftAnthropic.AnthropicService) {
        self.sdkService = sdkService
        self.settingsManager = nil
    }

    func streamChat(
        messages: [ChatMessage],
        systemPrompt: String,
        tools: [ToolDefinition]?,
        model: String,
        thinkingBudget: Int?
    ) -> AsyncThrowingStream<StreamingEvent, Error> {
        // Resolve SDK service. When settingsManager is present, read the API key
        // at call time so keys entered after app launch are always picked up.
        let resolvedSDKService: any SwiftAnthropic.AnthropicService
        if let settings = settingsManager {
            let key = settings.apiKey
            guard !key.isEmpty else {
                return AsyncThrowingStream { continuation in
                    continuation.yield(.error(AnthropicError.missingAPIKey))
                    continuation.finish()
                }
            }
            resolvedSDKService = AnthropicServiceFactory.service(apiKey: key, betaHeaders: nil)
        } else if let existing = sdkService {
            resolvedSDKService = existing
        } else {
            return AsyncThrowingStream { continuation in
                continuation.yield(.error(AnthropicError.missingAPIKey))
                continuation.finish()
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let sdkMessages = messages.compactMap { msg -> MessageParameter.Message? in
                        switch msg.role {
                        case .user:
                            return MessageParameter.Message(role: .user, content: .text(msg.content))
                        case .assistant:
                            return MessageParameter.Message(role: .assistant, content: .text(msg.content))
                        case .system:
                            return nil // system messages go in systemPrompt
                        }
                    }

                    let sdkTools: [MessageParameter.Tool]? = tools.map { defs in
                        defs.map { def in
                            let schema = buildJSONSchema(fromJSON: def.inputSchemaJSON)
                            return .function(name: def.name, description: def.description, inputSchema: schema)
                        }
                    }

                    let sdkThinking: MessageParameter.Thinking? = thinkingBudget.map {
                        MessageParameter.Thinking(budgetTokens: $0)
                    }
                    let maxTokens = thinkingBudget.map { max(4096, $0 + 4096) } ?? 4096

                    let parameter = MessageParameter(
                        model: .other(model),
                        messages: sdkMessages,
                        maxTokens: maxTokens,
                        system: .text(systemPrompt),
                        stream: true,
                        tools: sdkTools,
                        thinking: sdkThinking
                    )

                    let stream = try await resolvedSDKService.streamMessage(parameter)

                    // Accumulate tool input JSON across delta events
                    var toolUseId: String?
                    var toolUseName: String?
                    var toolInputAccumulator = ""

                    for try await event in stream {
                        switch event.streamEvent {
                        case .contentBlockStart:
                            if let block = event.contentBlock {
                                if block.type == "tool_use" {
                                    toolUseId = block.id
                                    toolUseName = block.name
                                    toolInputAccumulator = ""
                                }
                            }
                        case .contentBlockDelta:
                            if let delta = event.delta {
                                if event.isThinkingDelta, let thinkingChunk = delta.thinking {
                                    continuation.yield(.thinking(thinkingChunk))
                                } else if let text = delta.text {
                                    continuation.yield(.text(text))
                                } else if let partialJson = delta.partialJson {
                                    toolInputAccumulator += partialJson
                                }
                            }
                        case .contentBlockStop:
                            if let id = toolUseId, let name = toolUseName {
                                continuation.yield(.toolUse(id: id, name: name, inputJSON: toolInputAccumulator))
                                toolUseId = nil
                                toolUseName = nil
                                toolInputAccumulator = ""
                            }
                        case .messageStop:
                            continuation.yield(.complete)
                        case .messageStart, .messageDelta, .none:
                            break
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

    // MARK: - Private Helpers

    private func buildJSONSchema(fromJSON jsonString: String) -> JSONSchema? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return buildJSONSchemaFromDict(dict)
    }

    private func buildJSONSchemaFromDict(_ dict: [String: Any]) -> JSONSchema? {
        guard let typeString = dict["type"] as? String,
              let jsonType = jsonTypeFrom(string: typeString) else {
            return nil
        }

        var properties: [String: SwiftAnthropic.JSONSchema.Property]?
        if let propsDict = dict["properties"] as? [String: Any] {
            var result: [String: SwiftAnthropic.JSONSchema.Property] = [:]
            for (key, value) in propsDict {
                if let propDict = value as? [String: Any],
                   let prop = buildProperty(from: propDict) {
                    result[key] = prop
                }
            }
            properties = result.isEmpty ? nil : result
        }

        let required = dict["required"] as? [String]

        return SwiftAnthropic.JSONSchema(
            type: jsonType,
            properties: properties,
            required: required
        )
    }

    private func buildProperty(from dict: [String: Any]) -> SwiftAnthropic.JSONSchema.Property? {
        guard let typeString = dict["type"] as? String,
              let jsonType = jsonTypeFrom(string: typeString) else {
            return nil
        }
        let description = dict["description"] as? String
        let enumValues = dict["enum"] as? [String]
        return SwiftAnthropic.JSONSchema.Property(
            type: jsonType,
            description: description,
            enumValues: enumValues
        )
    }

    private func jsonTypeFrom(string: String) -> SwiftAnthropic.JSONSchema.JSONType? {
        switch string {
        case "string": return .string
        case "integer": return .integer
        case "number": return .number
        case "boolean": return .boolean
        case "object": return .object
        case "array": return .array
        case "null": return .null
        default: return nil
        }
    }
}
