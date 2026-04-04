import Foundation

// MARK: - CreateProgramTool

struct CreateProgramTool: ClaudeTool {

    static let toolName = "create_program"
    static let toolDescription = "Create a multi-day training program as multiple workout templates. Returns a summary awaiting user confirmation before saving."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "program_name": {
          "type": "string",
          "description": "Name of the training program"
        },
        "templates": {
          "type": "array",
          "description": "Templates in the program",
          "items": {
            "type": "object",
            "properties": {
              "template_name": { "type": "string" },
              "exercises": {
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "name": { "type": "string" },
                    "sets": { "type": "integer" },
                    "reps": { "type": "integer" },
                    "weight": { "type": "number" }
                  },
                  "required": ["name"]
                }
              }
            },
            "required": ["template_name", "exercises"]
          }
        }
      },
      "required": ["program_name", "templates"]
    }
    """

    func execute(inputJSON: String, context: ToolContext) async throws -> String {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let programName = json["program_name"] as? String else {
            return "Error: missing required parameter program_name"
        }

        guard let templatesInput = json["templates"] as? [[String: Any]], !templatesInput.isEmpty else {
            return "Error: program must have at least one template"
        }

        var templateSummaries: [String] = []

        for templateInput in templatesInput {
            guard let templateName = templateInput["template_name"] as? String else { continue }
            let exerciseInputs = templateInput["exercises"] as? [[String: Any]] ?? []
            var resolvedNames: [String] = []

            for exerciseInput in exerciseInputs {
                guard let name = exerciseInput["name"] as? String else { continue }
                let matches = try await context.exerciseRepository.fuzzySearch(query: name)
                if let exercise = matches.first {
                    let sets = exerciseInput["sets"] as? Int ?? 3
                    let reps = exerciseInput["reps"] as? Int ?? 10
                    resolvedNames.append("\(exercise.name) (\(sets)×\(reps))")
                }
            }

            let exerciseSummary = resolvedNames.isEmpty ? "no matched exercises" : resolvedNames.joined(separator: ", ")
            templateSummaries.append("  - \(templateName): \(exerciseSummary)")
        }

        let templateList = templateSummaries.joined(separator: "\n")
        return "Program '\(programName)' with \(templateSummaries.count) template(s):\n\(templateList)\nAwaiting confirmation."
    }

    // Builds the WorkoutTemplate objects for saving
    func buildTemplates(inputJSON: String, exerciseRepository: any ExerciseRepository) async throws -> [WorkoutTemplate] {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let templatesInput = json["templates"] as? [[String: Any]] else {
            return []
        }

        let helper = CreateTemplateTool()
        var templates: [WorkoutTemplate] = []

        for templateInput in templatesInput {
            guard let templateName = templateInput["template_name"] as? String else { continue }
            let exercises = templateInput["exercises"] as? [[String: Any]] ?? []
            let syntheticJSON = try JSONSerialization.data(withJSONObject: [
                "template_name": templateName,
                "exercises": exercises
            ])
            guard let syntheticString = String(data: syntheticJSON, encoding: .utf8),
                  let template = try await helper.buildTemplate(inputJSON: syntheticString, exerciseRepository: exerciseRepository) else {
                continue
            }
            templates.append(template)
        }

        return templates
    }
}
