import Foundation

// MARK: - StartWorkoutTool

struct StartWorkoutTool: ClaudeTool {

    static let toolName = "start_workout"
    static let toolDescription = "Start a workout session from a saved template. The user can say something like 'start my push day'."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "template_name": {
          "type": "string",
          "description": "Name of the workout template to start"
        }
      },
      "required": ["template_name"]
    }
    """

    func execute(inputJSON: String, context: ToolContext) async throws -> String {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let templateName = json["template_name"] as? String else {
            return "Error: missing required parameter template_name"
        }

        // Can't start a second workout
        guard context.activeWorkout == nil else {
            return "You already have an active workout. Finish or cancel it first."
        }

        let allTemplates = try await context.templateRepository.fetchAll()

        // Exact case-insensitive match first
        let lowered = templateName.lowercased()
        if let exact = allTemplates.first(where: { $0.name.lowercased() == lowered }) {
            return await startFromTemplate(exact, context: context)
        }

        // Contains-match fallback
        let containsMatches = allTemplates.filter { $0.name.lowercased().contains(lowered) }
        if containsMatches.count == 1 {
            return await startFromTemplate(containsMatches[0], context: context)
        }

        if containsMatches.count > 1 {
            let names = containsMatches.map { "'\($0.name)'" }.joined(separator: ", ")
            return "Multiple templates match '\(templateName)': \(names). Please be more specific."
        }

        // No match — list available templates
        let available = allTemplates.prefix(5).map { $0.name }.joined(separator: ", ")
        if available.isEmpty {
            return "No template found matching '\(templateName)'. You don't have any saved templates."
        }
        return "No template found matching '\(templateName)'. Available templates: \(available)"
    }

    private func startFromTemplate(_ template: WorkoutTemplate, context: ToolContext) async -> String {
        guard let callback = context.onStartWorkout else {
            return "Unable to start workout from this context."
        }
        await callback(template)
        return "Started workout '\(template.name)' with \(template.exercises.count) exercises."
    }
}
