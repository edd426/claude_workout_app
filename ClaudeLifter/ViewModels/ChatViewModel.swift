import Foundation
import Observation

// MARK: - ChatViewModel

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Published State

    var messages: [ChatMessage] = []
    var currentStreamingText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var activeWorkoutContext: String?

    // MARK: - Dependencies

    private let anthropicService: any AnthropicServiceProtocol
    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let preferenceRepository: any TrainingPreferenceRepository
    private let tools: [any ClaudeTool]

    /// The active workout session used by tools. Set externally when a workout is in progress.
    var activeWorkout: Workout? {
        didSet {
            activeWorkoutContext = activeWorkout?.name
        }
    }

    // MARK: - Model Selection

    var selectedModel: String {
        get { UserDefaults.standard.string(forKey: "chat_model") ?? "claude-haiku-4-5-20251001" }
        set { UserDefaults.standard.set(newValue, forKey: "chat_model") }
    }

    // MARK: - Init

    init(
        anthropicService: any AnthropicServiceProtocol,
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        preferenceRepository: any TrainingPreferenceRepository,
        tools: [any ClaudeTool]? = nil
    ) {
        self.anthropicService = anthropicService
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.preferenceRepository = preferenceRepository
        self.tools = tools ?? [
            GetExerciseHistoryTool(),
            GetRecentWorkoutsTool(),
            SuggestWeightTool(),
            AddExerciseTool(),
            RemoveExerciseTool()
        ]
    }

    // MARK: - Public API

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        isLoading = true
        errorMessage = nil

        do {
            try await streamResponse()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func clearChat() {
        messages = []
        currentStreamingText = ""
        errorMessage = nil
        isLoading = false
    }

    // MARK: - Private

    private func streamResponse() async throws {
        let systemPrompt = buildSystemPrompt()
        let toolDefs = tools.map { $0.definition }

        var accumulatedText = ""
        var pendingToolId: String?
        var pendingToolName: String?
        var pendingToolJSON: String?

        let stream = anthropicService.streamChat(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: toolDefs,
            model: selectedModel
        )

        for try await event in stream {
            switch event {
            case .text(let chunk):
                accumulatedText += chunk
                currentStreamingText = accumulatedText

            case .toolUse(let id, let name, let inputJSON):
                // If we have accumulated text, finalise it as an assistant message first
                if !accumulatedText.isEmpty {
                    let assistantMsg = ChatMessage(role: .assistant, content: accumulatedText)
                    messages.append(assistantMsg)
                    accumulatedText = ""
                    currentStreamingText = ""
                }
                pendingToolId = id
                pendingToolName = name
                pendingToolJSON = inputJSON

            case .complete:
                // Finalise any remaining streamed text
                if !accumulatedText.isEmpty {
                    let assistantMsg = ChatMessage(role: .assistant, content: accumulatedText)
                    messages.append(assistantMsg)
                    accumulatedText = ""
                    currentStreamingText = ""
                }

                // Execute pending tool if any
                if let toolId = pendingToolId, let toolName = pendingToolName, let toolJSON = pendingToolJSON {
                    let result = await executeTool(name: toolName, inputJSON: toolJSON)
                    // Add tool result as a system-style message for context
                    let resultMessage = ChatMessage(role: .system, content: "[Tool: \(toolName)] \(result)")
                    messages.append(resultMessage)
                    pendingToolId = nil
                    pendingToolName = nil
                    pendingToolJSON = nil

                    // Send a follow-up to Claude with the tool result
                    try await sendToolResult(toolId: toolId, toolName: toolName, result: result, systemPrompt: systemPrompt)
                }

            case .error(let error):
                throw error
            }
        }

        isLoading = false
    }

    private func sendToolResult(toolId: String, toolName: String, result: String, systemPrompt: String) async throws {
        // Add the tool result to the conversation and get Claude's follow-up
        var accumulatedText = ""

        let stream = anthropicService.streamChat(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools.map { $0.definition },
            model: selectedModel
        )

        for try await event in stream {
            switch event {
            case .text(let chunk):
                accumulatedText += chunk
                currentStreamingText = accumulatedText
            case .complete:
                if !accumulatedText.isEmpty {
                    let msg = ChatMessage(role: .assistant, content: accumulatedText)
                    messages.append(msg)
                    currentStreamingText = ""
                }
            case .toolUse, .error:
                break
            }
        }
    }

    private func executeTool(name: String, inputJSON: String) async -> String {
        let context = ToolContext(
            exerciseRepository: exerciseRepository,
            workoutRepository: workoutRepository,
            templateRepository: templateRepository,
            activeWorkout: activeWorkout
        )
        guard let tool = tools.first(where: { type(of: $0).toolName == name }) else {
            return "Error: unknown tool '\(name)'"
        }
        do {
            return try await tool.execute(inputJSON: inputJSON, context: context)
        } catch {
            return "Tool error: \(error.localizedDescription)"
        }
    }

    private var cachedPreferences: [TrainingPreference] = []

    func loadPreferences() async {
        cachedPreferences = (try? await preferenceRepository.fetchAll()) ?? []
    }

    private func buildSystemPrompt() -> String {
        var parts: [String] = []

        // Static cached portion
        parts.append("""
        You are an expert personal trainer and exercise scientist with deep knowledge of progressive overload, periodization, rep ranges, RPE, and recovery. You help the user track and improve their strength training.

        Guidelines:
        - Give actionable, specific advice based on the user's actual workout data
        - Use metric units by default (kg) unless the user's data shows lbs
        - Be encouraging but honest about progress
        - When modifying the active workout, use the available tools directly — no confirmation needed
        - When suggesting new templates, summarize what you'd create and ask for confirmation before saving
        - Do not delete templates under any circumstances
        """)

        // Training preferences
        if !cachedPreferences.isEmpty {
            let prefLines = cachedPreferences.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
            parts.append("User training preferences:\n\(prefLines)")
        }

        // Active workout context
        if let workout = activeWorkout {
            var workoutLines = ["Active workout: \(workout.name)"]
            for we in workout.exercises.sorted(by: { $0.order < $1.order }) {
                let exerciseName = we.exercise?.name ?? "Unknown"
                let completedSets = we.sets.filter { $0.isCompleted }.count
                workoutLines.append("  - \(exerciseName): \(completedSets)/\(we.sets.count) sets completed")
            }
            parts.append(workoutLines.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }
}
