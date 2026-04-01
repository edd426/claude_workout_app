import Foundation
@testable import ClaudeLifter

final class MockAnthropicService: AnthropicServiceProtocol, @unchecked Sendable {

    // MARK: - Configuration

    /// Events to yield in order when streamChat is called.
    var stubbedEvents: [StreamingEvent] = [.text("Hello from Claude!"), .complete]

    /// If set, throws this error instead of yielding events.
    var stubbedError: Error?

    // MARK: - Recorded Calls

    var streamChatCallCount = 0
    var lastMessages: [ChatMessage] = []
    var lastSystemPrompt: String = ""
    var lastTools: [ToolDefinition]?
    var lastModel: String = ""
    var lastThinkingBudget: Int?

    // MARK: - AnthropicServiceProtocol

    func streamChat(
        messages: [ChatMessage],
        systemPrompt: String,
        tools: [ToolDefinition]?,
        model: String,
        thinkingBudget: Int?
    ) -> AsyncThrowingStream<StreamingEvent, Error> {
        streamChatCallCount += 1
        lastMessages = messages
        lastSystemPrompt = systemPrompt
        lastTools = tools
        lastModel = model
        lastThinkingBudget = thinkingBudget

        let events = stubbedEvents
        let error = stubbedError

        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
