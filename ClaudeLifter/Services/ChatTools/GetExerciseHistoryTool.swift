import Foundation

// MARK: - GetExerciseHistoryTool

struct GetExerciseHistoryTool: ClaudeTool {

    static let toolName = "get_exercise_history"
    static let toolDescription = "Get the history of sets performed for a given exercise. Returns the most recent sets with weight, reps, and date."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "exercise_name": {
          "type": "string",
          "description": "The name of the exercise to look up history for"
        },
        "limit": {
          "type": "integer",
          "description": "Maximum number of sets to return (default: 20)"
        }
      },
      "required": ["exercise_name"]
    }
    """

    func execute(inputJSON: String, context: ToolContext) async throws -> String {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exerciseName = json["exercise_name"] as? String else {
            return "Error: missing required parameter exercise_name"
        }
        let limit = json["limit"] as? Int ?? 20

        // Search for exercise by name
        let exercises = try await context.exerciseRepository.search(query: exerciseName)
        guard let exercise = exercises.first else {
            return "No exercise found matching '\(exerciseName)'"
        }

        let sets = try await context.workoutRepository.recentSets(for: exercise.id, limit: limit)
        if sets.isEmpty {
            return "No history found for '\(exercise.name)'"
        }

        var lines = ["History for \(exercise.name) (last \(sets.count) sets):"]
        for set in sets {
            let weight = set.weight.map { "\($0)\(set.weightUnit.rawValue)" } ?? "bodyweight"
            let reps = set.reps.map { "\($0) reps" } ?? "no reps recorded"
            lines.append("  - \(weight) x \(reps)")
        }
        return lines.joined(separator: "\n")
    }
}
