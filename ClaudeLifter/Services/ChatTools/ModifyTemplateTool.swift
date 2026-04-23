import Foundation

// MARK: - ModifyTemplateTool

struct ModifyTemplateTool: ClaudeTool {

    static let toolName = "modify_template"
    static let toolDescription = "Modify an existing workout template. Only used when the user explicitly asks to change a saved template. Returns a description awaiting confirmation."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "template_name": {
          "type": "string",
          "description": "Name of the template to modify"
        },
        "action": {
          "type": "string",
          "enum": ["add_exercise", "remove_exercise", "rename"],
          "description": "The modification to perform"
        },
        "exercise_name": {
          "type": "string",
          "description": "Exercise name (required for add_exercise and remove_exercise actions)"
        },
        "new_name": {
          "type": "string",
          "description": "New template name (required for rename action)"
        },
        "sets": {
          "type": "integer",
          "description": "Number of sets (for add_exercise)"
        },
        "reps": {
          "type": "integer",
          "description": "Number of reps (for add_exercise)"
        }
      },
      "required": ["template_name", "action"]
    }
    """

    func execute(inputJSON: String, context: ToolContext) async throws -> String {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let templateName = json["template_name"] as? String,
              let action = json["action"] as? String else {
            return "Error: missing required parameters template_name and action"
        }

        let templates = try await context.templateRepository.fetchAll()
        guard let template = templates.first(where: { $0.name.localizedCaseInsensitiveCompare(templateName) == .orderedSame }) else {
            return "Error: no template found with name '\(templateName)'"
        }

        switch action {
        case "add_exercise":
            guard let exerciseName = json["exercise_name"] as? String else {
                return "Error: exercise_name is required for add_exercise action"
            }
            let sets = json["sets"] as? Int ?? 3
            let reps = json["reps"] as? Int ?? 10

            let matches = try await context.exerciseRepository.fuzzySearch(query: exerciseName)
            guard let exercise = matches.first else {
                return "Error: no exercise found matching '\(exerciseName)'"
            }

            return "Add '\(exercise.name)' (\(sets)×\(reps)) to template '\(template.name)'. Awaiting confirmation."

        case "remove_exercise":
            guard let exerciseName = json["exercise_name"] as? String else {
                return "Error: exercise_name is required for remove_exercise action"
            }

            let found = template.exercises.first {
                $0.exercise?.name.localizedCaseInsensitiveContains(exerciseName) == true
            }
            guard let te = found else {
                return "Error: '\(exerciseName)' is not in template '\(template.name)'"
            }

            return "Remove '\(te.exercise?.name ?? exerciseName)' from template '\(template.name)'. Awaiting confirmation."

        case "rename":
            guard let newName = json["new_name"] as? String else {
                return "Error: new_name is required for rename action"
            }

            return "Rename template '\(template.name)' to '\(newName)'. Awaiting confirmation."

        default:
            return "Error: unknown action '\(action)'. Use add_exercise, remove_exercise, or rename."
        }
    }

    // Applies the modification and saves. Called from the confirmation closure.
    func applyAndSave(inputJSON: String, templateRepository: any TemplateRepository, exerciseRepository: any ExerciseRepository) async throws -> String {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let templateName = json["template_name"] as? String,
              let action = json["action"] as? String else {
            return "Error: invalid input"
        }

        let templates = try await templateRepository.fetchAll()
        guard let template = templates.first(where: { $0.name.localizedCaseInsensitiveCompare(templateName) == .orderedSame }) else {
            return "Error: template not found"
        }

        switch action {
        case "add_exercise":
            guard let exerciseName = json["exercise_name"] as? String else { return "Error: exercise_name missing" }
            let sets = json["sets"] as? Int ?? 3
            let reps = json["reps"] as? Int ?? 10

            let matches = try await exerciseRepository.fuzzySearch(query: exerciseName)
            guard let exercise = matches.first else { return "Error: exercise not found" }

            let newOrder = (template.exercises.map { $0.order }.max() ?? -1) + 1
            let te = TemplateExercise(order: newOrder, exercise: exercise, defaultSets: sets, defaultReps: reps)
            template.exercises.append(te)
            template.updatedAt = .now
            template.recordChange()
            try await templateRepository.save(template)
            return "Added '\(exercise.name)' to '\(template.name)'."

        case "remove_exercise":
            guard let exerciseName = json["exercise_name"] as? String else { return "Error: exercise_name missing" }
            template.exercises.removeAll { $0.exercise?.name.localizedCaseInsensitiveContains(exerciseName) == true }
            template.updatedAt = .now
            template.recordChange()
            try await templateRepository.save(template)
            return "Removed '\(exerciseName)' from '\(template.name)'."

        case "rename":
            guard let newName = json["new_name"] as? String else { return "Error: new_name missing" }
            template.name = newName
            template.updatedAt = .now
            template.recordChange()
            try await templateRepository.save(template)
            return "Renamed template to '\(newName)'."

        default:
            return "Error: unknown action"
        }
    }
}
