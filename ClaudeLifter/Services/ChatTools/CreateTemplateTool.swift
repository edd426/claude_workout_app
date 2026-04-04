import Foundation

// MARK: - CreateTemplateTool

struct CreateTemplateTool: ClaudeTool {

    static let toolName = "create_template"
    static let toolDescription = "Create a new workout template with exercises. Returns a summary awaiting user confirmation before saving."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "template_name": {
          "type": "string",
          "description": "Name of the template"
        },
        "exercises": {
          "type": "array",
          "description": "Exercises in the template",
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
    """

    func execute(inputJSON: String, context: ToolContext) async throws -> String {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let templateName = json["template_name"] as? String else {
            return "Error: missing required parameter template_name"
        }

        let exerciseInputs = json["exercises"] as? [[String: Any]] ?? []
        var resolvedLines: [String] = []
        var unmatchedNames: [String] = []

        for exerciseInput in exerciseInputs {
            guard let name = exerciseInput["name"] as? String else { continue }
            let sets = exerciseInput["sets"] as? Int ?? 3
            let reps = exerciseInput["reps"] as? Int ?? 10

            let matches = try await context.exerciseRepository.fuzzySearch(query: name)
            let exercise = matches.first(where: { $0.name.lowercased() == name.lowercased() }) ?? matches.first
            if let exercise {
                resolvedLines.append("\(exercise.name) (\(sets)×\(reps))")
            } else {
                unmatchedNames.append(name)
            }
        }

        if resolvedLines.isEmpty && !exerciseInputs.isEmpty {
            let tried = unmatchedNames.joined(separator: ", ")
            return "Error: could not create template '\(templateName)' — none of these exercises were found in the library: \(tried). Use the search_exercises tool to find the correct names first."
        }

        var result = "Template '\(templateName)' with \(resolvedLines.count) exercise(s): \(resolvedLines.joined(separator: ", "))."
        if !unmatchedNames.isEmpty {
            result += " WARNING: These exercises were NOT found and were skipped: \(unmatchedNames.joined(separator: ", ")). Use search_exercises to find correct names."
        }
        result += " Awaiting confirmation."
        return result
    }

    // Builds the actual WorkoutTemplate + TemplateExercise objects for saving
    func buildTemplate(inputJSON: String, exerciseRepository: any ExerciseRepository) async throws -> WorkoutTemplate? {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let templateName = json["template_name"] as? String else {
            return nil
        }

        let template = WorkoutTemplate(name: templateName)
        let exerciseInputs = json["exercises"] as? [[String: Any]] ?? []
        var order = 0

        for exerciseInput in exerciseInputs {
            guard let name = exerciseInput["name"] as? String else { continue }
            let sets = exerciseInput["sets"] as? Int ?? 3
            let reps = exerciseInput["reps"] as? Int ?? 10
            let weight = exerciseInput["weight"] as? Double

            let matches = try await exerciseRepository.fuzzySearch(query: name)
            // (#38 fix) Prefer exact match
            guard let exercise = matches.first(where: { $0.name.lowercased() == name.lowercased() }) ?? matches.first else { continue }

            let te = TemplateExercise(
                order: order,
                exercise: exercise,
                defaultSets: sets,
                defaultReps: reps,
                defaultWeight: weight
            )
            template.exercises.append(te)
            order += 1
        }

        // Return nil when no exercises were matched — caller must handle this case
        if template.exercises.isEmpty {
            return nil
        }

        return template
    }
}
