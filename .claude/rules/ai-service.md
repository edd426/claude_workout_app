# AI Service Patterns

## SwiftAnthropic SDK

The app uses [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) for Claude API access.

### Protocol-Based Design

```swift
protocol AnthropicServiceProtocol {
    func chat(
        messages: [ChatMessage],
        model: String,
        tools: [ChatTool]?
    ) -> AsyncThrowingStream<StreamingResponse, Error>

    func chatSync(
        messages: [ChatMessage],
        model: String
    ) async throws -> String
}
```

- Production implementation wraps SwiftAnthropic SDK
- Test mock returns canned responses or errors
- ViewModel receives protocol via init, never the concrete type

### API Key Security
- **Phase 1**: API key stored on-device (acceptable for personal app, not App Store)
- **Phase 2**: Key moves to Azure Function, app calls proxy endpoint

## System Prompt Structure

```
[CACHED — static portion, loaded once per session]
- Role definition (expert personal trainer)
- Exercise science domain knowledge
- Output format rules
- Tool schemas
- Training preferences (from TrainingPreference entity)

[DYNAMIC — appended per request]
- Active workout state (if any): exercise list, sets completed
- User's message
```

Use Anthropic prompt caching: mark the static portion with `cache_control` to get ~90% read discount.

## Chat Session Lifecycle
- Chat history is per-session — full messages kept, no truncation
- On session end (workout completed or user navigates away), chat clears
- TrainingPreferences persist across sessions — loaded into system prompt

## Model Selection
- User-configurable in Settings (see SPEC.md §6.1)
- Default: Haiku for routine queries, Sonnet for coaching
- Model picker shows cost indicator ($, $$, $$$)
- Store preference in UserDefaults

## Tool Definitions

Each Claude tool is a struct conforming to a protocol:

```swift
protocol ClaudeTool {
    static var name: String { get }
    static var description: String { get }
    static var inputSchema: [String: Any] { get }

    func execute(input: [String: Any], context: ToolContext) async throws -> String
}
```

Tools available to Claude (SPEC.md §6.1):
- `get_exercise_history` — past sets for an exercise
- `get_recent_workouts` — summaries of recent sessions
- `suggest_weight` — recommended weight based on history
- `add_exercise_to_workout` — modify active session
- `remove_exercise_from_workout` — modify active session
- `create_template` — create a new workout template (requires confirmation)

## Streaming Responses

Use AsyncThrowingStream for streaming chat responses:
- ChatViewModel updates `currentResponse` as tokens arrive
- UI renders partial response in real-time
- Tool calls are detected mid-stream and executed

## Cost Tracking
- Track input/output tokens per request from API response
- Aggregate per-session and per-month
- Optional display in Settings
