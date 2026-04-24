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
    var useExtendedThinking: Bool = false
    var currentConversationId: UUID = UUID()

    // MARK: - Dependencies

    private let anthropicService: any AnthropicServiceProtocol
    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let preferenceRepository: any TrainingPreferenceRepository
    private let chatRepository: (any ChatMessageRepository)?
    private let tools: [any ClaudeTool]
    private let settings: SettingsManager?
    private let appState: AppState?
    private let autoFillService: (any AutoFillServiceProtocol)?

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
        chatRepository: (any ChatMessageRepository)? = nil,
        tools: [any ClaudeTool]? = nil,
        settings: SettingsManager? = nil,
        appState: AppState? = nil,
        autoFillService: (any AutoFillServiceProtocol)? = nil
    ) {
        self.anthropicService = anthropicService
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.preferenceRepository = preferenceRepository
        self.chatRepository = chatRepository
        self.settings = settings
        self.appState = appState
        self.autoFillService = autoFillService
        self.tools = tools ?? [
            SearchExercisesTool(),
            GetExerciseHistoryTool(),
            GetRecentWorkoutsTool(),
            SuggestWeightTool(),
            AddExerciseTool(),
            RemoveExerciseTool(),
            SetExerciseTargetsTool(),
            LogSetTool(),
            StartWorkoutTool(),
            EndWorkoutTool(),
            CreateTemplateTool(),
            CreateProgramTool(),
            ModifyTemplateTool()
        ]
    }

    // MARK: - Public API

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Refuse a second send while one is already streaming — otherwise two
        // handleToolChain loops race, duplicate the user message, and may
        // produce interleaved assistant text that never finalises.
        guard !isLoading else { return }

        let userMessage = ChatMessage(role: .user, text: text)
        messages.append(userMessage)
        persistMessage(userMessage)
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
        Task { try? await chatRepository?.deleteAll(workoutId: activeWorkout?.id) }
    }

    func loadHistory() async {
        guard messages.isEmpty else { return }
        guard let repo = chatRepository else { return }
        let saved = (try? await repo.fetch(workoutId: activeWorkout?.id)) ?? []
        let filtered = saved.filter { $0.conversationId == currentConversationId }
        messages = filtered.suffix(50).map {
            ChatMessage(role: $0.role, text: $0.content, timestamp: $0.timestamp)
        }
    }

    // MARK: - Conversation Management

    func startNewConversation() {
        currentConversationId = UUID()
        messages = []
        currentStreamingText = ""
        errorMessage = nil
        isLoading = false
    }

    func loadConversation(id: UUID) async {
        currentConversationId = id
        messages = []
        guard let repo = chatRepository else { return }
        let all = (try? await repo.fetch(workoutId: activeWorkout?.id)) ?? []
        let filtered = all.filter { $0.conversationId == id }
        messages = filtered.suffix(50).map {
            ChatMessage(role: $0.role, text: $0.content, timestamp: $0.timestamp)
        }
    }

    func listConversations() async -> [(id: UUID, preview: String, date: Date)] {
        guard let repo = chatRepository else { return [] }
        let all = (try? await repo.fetch(workoutId: activeWorkout?.id)) ?? []
        // Group by conversationId
        var grouped: [UUID: [AIChatMessage]] = [:]
        for msg in all {
            let convoId = msg.conversationId ?? UUID()
            grouped[convoId, default: []].append(msg)
        }
        // Build summaries, sorted by most recent first
        return grouped.compactMap { convoId, msgs in
            guard let first = msgs.sorted(by: { $0.timestamp < $1.timestamp }).first else { return nil }
            let preview = String(first.content.prefix(80))
            let latestDate = msgs.map(\.timestamp).max() ?? first.timestamp
            return (id: convoId, preview: preview, date: latestDate)
        }
        .sorted { $0.date > $1.date }
        .prefix(50)
        .map { $0 }
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

        trimMessagesIfNeeded()
        isLoading = false
    }

    /// Keep only the last 100 messages to bound memory growth during long sessions (#71).
    private func trimMessagesIfNeeded() {
        let maxMessages = 100
        if messages.count > maxMessages {
            messages = Array(messages.suffix(maxMessages))
        }
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
                    persistMessage(assistantMsg)
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
                    persistMessage(assistantMsg)
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
                    } else {
                        // Previously silent — the user saw nothing after 5 tools
                        // and had no idea the chain had been cut off. Surface it.
                        let noticeText = "I've hit the tool-chain depth limit (\(5)). If you need me to keep going, just say \"continue.\""
                        let notice = ChatMessage(role: .assistant, text: noticeText)
                        messages.append(notice)
                        persistMessage(notice)
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
            activeWorkout: activeWorkout,
            onStartWorkout: { [weak self] template in
                guard let self, let appState = self.appState, let autoFillService = self.autoFillService else { return }
                let vm = ActiveWorkoutViewModel(
                    template: template,
                    workoutRepository: self.workoutRepository,
                    autoFillService: autoFillService,
                    templateRepository: self.templateRepository
                )
                await vm.startWorkout()
                appState.startWorkout(id: vm.workout?.id ?? UUID(), vm: vm)
                self.activeWorkout = vm.workout
            }
        )
        guard let tool = tools.first(where: { type(of: $0).toolName == name }) else {
            return "Error: unknown tool '\(name)'"
        }

        // Auto-save tools: execute for summary, then build and save directly
        if name == CreateTemplateTool.toolName {
            let createTool = CreateTemplateTool()
            do {
                let summary = try await createTool.execute(inputJSON: inputJSON, context: context)
                if summary.hasPrefix("Error:") { return summary }
                if let template = try await createTool.buildTemplate(inputJSON: inputJSON, exerciseRepository: exerciseRepository) {
                    try await templateRepository.save(template)
                    return summary.replacingOccurrences(of: "Awaiting confirmation.", with: "Template saved successfully!")
                }
                return summary
            } catch {
                return "Tool error: \(error.localizedDescription)"
            }
        }

        if name == CreateProgramTool.toolName {
            let programTool = CreateProgramTool()
            do {
                let summary = try await programTool.execute(inputJSON: inputJSON, context: context)
                if summary.hasPrefix("Error:") { return summary }
                let templates = try await programTool.buildTemplates(inputJSON: inputJSON, exerciseRepository: exerciseRepository)
                for template in templates {
                    try await templateRepository.save(template)
                }
                return summary.replacingOccurrences(of: "Awaiting confirmation.", with: "Program saved successfully!")
            } catch {
                return "Tool error: \(error.localizedDescription)"
            }
        }

        if name == ModifyTemplateTool.toolName {
            let modifyTool = ModifyTemplateTool()
            do {
                let summary = try await modifyTool.execute(inputJSON: inputJSON, context: context)
                if summary.hasPrefix("Error:") { return summary }
                _ = try await modifyTool.applyAndSave(
                    inputJSON: inputJSON,
                    templateRepository: templateRepository,
                    exerciseRepository: exerciseRepository
                )
                return summary.replacingOccurrences(of: "Awaiting confirmation.", with: "Template updated successfully!")
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

    /// Persist a text message to the chat repository. Tool-use and tool-result messages are transient.
    private func persistMessage(_ message: ChatMessage) {
        guard case .text(let text) = message.content else { return }
        let dbMessage = AIChatMessage(
            role: message.role,
            content: text,
            workoutId: activeWorkout?.id,
            timestamp: message.timestamp
        )
        dbMessage.conversationId = currentConversationId
        Task {
            do {
                try await chatRepository?.save(dbMessage)
            } catch {
                // Don't silently drop the user's chat — at least make the
                // failure visible in logs so we can diagnose "chat history
                // disappeared" reports, instead of discarding the error.
                print("⚠️ ChatViewModel.persistMessage failed: \(error)")
            }
        }
    }

    private var cachedPreferences: [TrainingPreference] = []

    func loadPreferences() async {
        cachedPreferences = (try? await preferenceRepository.fetchAll()) ?? []
    }

    private func buildSystemPrompt() -> String {
        var parts: [String] = []

        // Identify which Claude version is answering. Anthropic models cannot
        // reliably introspect their own weights, so without this injection
        // the Coach would tell the user "I don't know which model I am" even
        // though the app already does.
        let modelIdentity: String = {
            if let known = AIModel(rawValue: selectedModel) {
                return known.displayName + " (identifier: \(selectedModel))"
            }
            return "Claude (identifier: \(selectedModel))"
        }()

        // Static cached portion
        parts.append("""
        You are an expert personal trainer and exercise scientist with deep knowledge of progressive overload, periodization, rep ranges, RPE, and recovery. You help the user track and improve their strength training.

        Model: You are \(modelIdentity). If the user asks which model they're chatting with, answer with this exact label — do not say you don't know your version.

        Guidelines:
        - Give actionable, specific advice based on the user's actual workout data
        - Use metric units by default (kg) unless the user's data shows lbs
        - Be encouraging but honest about progress
        - Use tools proactively — when the user asks you to modify a workout or create a template/program, just do it without asking first; the user can undo if needed
        - Do not delete templates under any circumstances
        - Before creating a template or program, use the search_exercises tool to look up the exact exercise names in the database. Do not guess exercise names — they must match exactly. For example, search for "squat" to find available variations, then use those exact names.
        - Formatting: the app's chat window only renders inline markdown (bold, italic, lists). Do NOT use markdown headers (`#`, `##`, `###`) — they render as literal "###" characters. Use **bold** for emphasis instead.

        After-tool behavior (IMPORTANT — always do this):
        - Immediately after any tool returns, write a short natural-language summary (1–3 sentences) to the user describing what you did, what you found, and what they should do next. Do not end your turn silently after a tool result — the user cannot see tool output directly.
        - For create_template / create_program: list the template name(s) and a one-line rationale (e.g. "Classic full-body strength routine, compound lifts first.").
        - For search_exercises: say which exercise you picked and why, or ask a clarifying question if multiple candidates match.
        - For log_set / start_workout / set_exercise_targets / add_exercise / remove_exercise / end_workout: briefly confirm what changed in the active workout.
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
