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
        var emptyTemplateNames: [String] = []

        for templateInput in templatesInput {
            guard let templateName = templateInput["template_name"] as? String else { continue }
            let exerciseInputs = CreateTemplateTool.normalizeExercises(from: templateInput)
            var resolvedNames: [String] = []
            var unmatchedNames: [String] = []

            for exerciseInput in exerciseInputs {
                guard let name = exerciseInput["name"] as? String else { continue }
                let matches = try await context.exerciseRepository.fuzzySearch(query: name)
                let exercise = matches.first(where: { $0.name.lowercased() == name.lowercased() }) ?? matches.first
                if let exercise {
                    let sets = exerciseInput["sets"] as? Int ?? 3
                    let reps = exerciseInput["reps"] as? Int ?? 10
                    resolvedNames.append("\(exercise.name) (\(sets)×\(reps))")
                } else {
                    unmatchedNames.append(name)
                }
            }

            if resolvedNames.isEmpty {
                emptyTemplateNames.append(templateName)
                templateSummaries.append("  - \(templateName): no matched exercises")
            } else {
                var summary = "  - \(templateName): \(resolvedNames.joined(separator: ", "))"
                if !unmatchedNames.isEmpty {
                    summary += " (skipped: \(unmatchedNames.joined(separator: ", ")))"
                }
                templateSummaries.append(summary)
            }
        }

        // If ALL templates resolved to zero exercises, return an error
        if emptyTemplateNames.count == templateSummaries.count {
            let tried = emptyTemplateNames.joined(separator: ", ")
            return "Error: could not create program '\(programName)' — no exercises matched in any template (\(tried)). Use search_exercises to find correct names first."
        }

        let templateList = templateSummaries.joined(separator: "\n")
        var result = "Program '\(programName)' with \(templateSummaries.count) template(s):\n\(templateList)"
        if !emptyTemplateNames.isEmpty {
            result += "\nWARNING: These templates had no matched exercises and will be skipped: \(emptyTemplateNames.joined(separator: ", ")). Use search_exercises to find correct names."
        }
        result += "\nAwaiting confirmation."
        return result
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
