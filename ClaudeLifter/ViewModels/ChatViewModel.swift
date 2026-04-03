import Foundation
import Observation

// MARK: - ToolError

enum ToolError: LocalizedError {
    case noMatchingExercises

    var errorDescription: String? {
        switch self {
        case .noMatchingExercises:
            return "Could not create template — no matching exercises found."
        }
    }
}

// MARK: - PendingConfirmation

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let toolName: String
    let description: String
    let onConfirm: () async throws -> Void
}

// MARK: - ChatViewModel

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Published State

    var messages: [ChatMessage] = []
    var currentStreamingText: String = ""
    var thinkingText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var activeWorkoutContext: String?
    var pendingConfirmation: PendingConfirmation?
    var useExtendedThinking: Bool = false

    // MARK: - Dependencies

    private let anthropicService: any AnthropicServiceProtocol
    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let preferenceRepository: any TrainingPreferenceRepository
    private let tools: [any ClaudeTool]
    private let settings: SettingsManager?

    /// The active workout session used by tools. Set externally when a workout is in progress.
    var activeWorkout: Workout? {
        didSet {
            activeWorkoutContext = activeWorkout?.name
        }
    }

    // MARK: - Model Selection (#45: use SettingsManager when available)

    var selectedModel: String {
        if let settings {
            return settings.aiModel.rawValue
        }
        return UserDefaults.standard.string(forKey: "chat_model") ?? AIModel.haiku.rawValue
    }

    // MARK: - Init

    init(
        anthropicService: any AnthropicServiceProtocol,
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        preferenceRepository: any TrainingPreferenceRepository,
        tools: [any ClaudeTool]? = nil,
        settings: SettingsManager? = nil
    ) {
        self.anthropicService = anthropicService
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.preferenceRepository = preferenceRepository
        self.settings = settings
        self.tools = tools ?? [
            GetExerciseHistoryTool(),
            GetRecentWorkoutsTool(),
            SuggestWeightTool(),
            AddExerciseTool(),
            RemoveExerciseTool(),
            CreateTemplateTool(),
            CreateProgramTool(),
            ModifyTemplateTool()
        ]
    }

    // MARK: - Public API

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, text: text)
        messages.append(userMessage)
        isLoading = true
        errorMessage = nil
        thinkingText = ""

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

    func confirmPendingAction() async {
        guard let confirmation = pendingConfirmation else { return }
        pendingConfirmation = nil
        do {
            try await confirmation.onConfirm()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelPendingAction() {
        pendingConfirmation = nil
    }

    // MARK: - Private

    private func streamResponse() async throws {
        let systemPrompt = buildSystemPrompt()
        let toolDefs = tools.map { $0.definition }
        let budget = useExtendedThinking ? 10000 : nil

        try await handleToolChain(
            systemPrompt: systemPrompt,
            toolDefs: toolDefs,
            thinkingBudget: budget,
            depth: 0
        )

        isLoading = false
    }

    /// Streams one Claude response, executes any tool, and recurses if needed.
    /// `depth` tracks how deep we are to enforce max 5 tool chain depth.
    private func handleToolChain(
        systemPrompt: String,
        toolDefs: [ToolDefinition],
        thinkingBudget: Int?,
        depth: Int
    ) async throws {
        var accumulatedText = ""
        var pendingToolId: String?
        var pendingToolName: String?
        var pendingToolJSON: String?

        let stream = anthropicService.streamChat(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: toolDefs,
            model: selectedModel,
            thinkingBudget: thinkingBudget
        )

        for try await event in stream {
            switch event {
            case .thinking(let chunk):
                thinkingText += chunk

            case .text(let chunk):
                accumulatedText += chunk
                currentStreamingText = accumulatedText

            case .toolUse(let id, let name, let inputJSON):
                // If we have accumulated text, finalise it first
                if !accumulatedText.isEmpty {
                    let assistantMsg = ChatMessage(role: .assistant, text: accumulatedText)
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
                    let assistantMsg = ChatMessage(role: .assistant, text: accumulatedText)
                    messages.append(assistantMsg)
                    accumulatedText = ""
                    currentStreamingText = ""
                }

                // Execute pending tool if any
                if let toolId = pendingToolId,
                   let toolName = pendingToolName,
                   let toolJSON = pendingToolJSON {
                    pendingToolId = nil
                    pendingToolName = nil
                    pendingToolJSON = nil

                    let result = await executeTool(name: toolName, inputJSON: toolJSON)

                    // Append assistant tool-use block (#29 fix: proper Anthropic protocol)
                    let toolUseMsg = ChatMessage(
                        role: .assistant,
                        content: .toolUse(id: toolId, name: toolName, input: toolJSON)
                    )
                    messages.append(toolUseMsg)

                    // Append user tool-result block (#29 fix: proper Anthropic protocol)
                    let toolResultMsg = ChatMessage(
                        role: .user,
                        content: .toolResult(toolUseId: toolId, content: result)
                    )
                    messages.append(toolResultMsg)

                    // Recurse for chained tool use (#30 fix), up to max depth 5
                    if depth < 5 {
                        try await handleToolChain(
                            systemPrompt: systemPrompt,
                            toolDefs: toolDefs,
                            thinkingBudget: thinkingBudget,
                            depth: depth + 1
                        )
                    }
                }

            case .error(let error):
                throw error
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

        // Confirmation-gated tools: execute for summary, then set pendingConfirmation
        if name == CreateTemplateTool.toolName {
            let createTool = CreateTemplateTool()
            do {
                let summary = try await createTool.execute(inputJSON: inputJSON, context: context)
                // If execute returned an error (e.g. 0 exercises matched), don't show confirmation
                if summary.hasPrefix("Error:") {
                    return summary
                }
                let capturedInputJSON = inputJSON
                let capturedExerciseRepo = exerciseRepository
                let capturedTemplateRepo = templateRepository
                pendingConfirmation = PendingConfirmation(
                    toolName: name,
                    description: summary,
                    onConfirm: {
                        guard let template = try await createTool.buildTemplate(
                            inputJSON: capturedInputJSON,
                            exerciseRepository: capturedExerciseRepo
                        ) else {
                            throw ToolError.noMatchingExercises
                        }
                        try await capturedTemplateRepo.save(template)
                    }
                )
                return summary
            } catch {
                return "Tool error: \(error.localizedDescription)"
            }
        }

        if name == CreateProgramTool.toolName {
            let programTool = CreateProgramTool()
            do {
                let summary = try await programTool.execute(inputJSON: inputJSON, context: context)
                if summary.hasPrefix("Error:") {
                    return summary
                }
                let capturedInputJSON = inputJSON
                let capturedExerciseRepo = exerciseRepository
                let capturedTemplateRepo = templateRepository
                pendingConfirmation = PendingConfirmation(
                    toolName: name,
                    description: summary,
                    onConfirm: {
                        let templates = try await programTool.buildTemplates(
                            inputJSON: capturedInputJSON,
                            exerciseRepository: capturedExerciseRepo
                        )
                        for template in templates {
                            try await capturedTemplateRepo.save(template)
                        }
                    }
                )
                return summary
            } catch {
                return "Tool error: \(error.localizedDescription)"
            }
        }

        if name == ModifyTemplateTool.toolName {
            let modifyTool = ModifyTemplateTool()
            do {
                let summary = try await modifyTool.execute(inputJSON: inputJSON, context: context)
                if summary.hasPrefix("Error:") {
                    return summary
                }
                let capturedInputJSON = inputJSON
                let capturedExerciseRepo = exerciseRepository
                let capturedTemplateRepo = templateRepository
                pendingConfirmation = PendingConfirmation(
                    toolName: name,
                    description: summary,
                    onConfirm: {
                        _ = try await modifyTool.applyAndSave(
                            inputJSON: capturedInputJSON,
                            templateRepository: capturedTemplateRepo,
                            exerciseRepository: capturedExerciseRepo
                        )
                    }
                )
                return summary
            } catch {
                return "Tool error: \(error.localizedDescription)"
            }
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
