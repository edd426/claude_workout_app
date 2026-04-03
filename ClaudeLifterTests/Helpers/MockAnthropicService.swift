import Foundation
@testable import ClaudeLifter

final class MockAnthropicService: AnthropicServiceProtocol, @unchecked Sendable {

    // MARK: - Configuration

    /// Events to yield on every call (used when stubbedEventSequences is empty).
    var stubbedEvents: [StreamingEvent] = [.text("Hello from Claude!"), .complete]

    /// Per-call event sequences. The first array is consumed on the first call,
    /// the second on the second call, etc. Falls back to `stubbedEvents` when exhausted.
    var stubbedEventSequences: [[StreamingEvent]] = []

    /// If set, throws this error instead of yielding events.
    var stubbedError: Error?

    // MARK: - Recorded Calls

    var streamChatCallCount = 0
    var lastMessages: [ChatMessage] = []
    var lastSystemPrompt: String = ""
    var lastTools: [ToolDefinition]?
    var lastModel: String = ""
    var lastThinkingBudget: Int?

    /// All recorded calls in order (messages snapshot per call)
    var allCallMessages: [[ChatMessage]] = []

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
        allCallMessages.append(messages)
        lastSystemPrompt = systemPrompt
        lastTools = tools
        lastModel = model
        lastThinkingBudget = thinkingBudget

        // Pick the right event set for this call
        let events: [StreamingEvent]
        if !stubbedEventSequences.isEmpty {
            events = stubbedEventSequences.removeFirst()
        } else {
            events = stubbedEvents
        }

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
