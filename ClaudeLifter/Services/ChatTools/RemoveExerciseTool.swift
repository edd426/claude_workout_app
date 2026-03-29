import Foundation

// MARK: - RemoveExerciseTool

struct RemoveExerciseTool: ClaudeTool {

    static let toolName = "remove_exercise_from_workout"
    static let toolDescription = "Remove an exercise from the currently active workout session. Does not modify the underlying template."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "exercise_name": {
          "type": "string",
          "description": "The name of the exercise to remove from the active workout"
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

        guard let workout = context.activeWorkout else {
            return "No active workout session. Start a workout first."
        }

        let lowercased = exerciseName.lowercased()
        let matchIndex = workout.exercises.firstIndex {
            $0.exercise?.name.lowercased().contains(lowercased) == true
        }

        guard let index = matchIndex else {
            return "'\(exerciseName)' was not found in your current workout."
        }

        let removedName = workout.exercises[index].exercise?.name ?? exerciseName
        workout.exercises.remove(at: index)
        // Re-index orders
        for (i, we) in workout.exercises.enumerated() {
            we.order = i
        }
        try await context.workoutRepository.save(workout)

        return "Removed '\(removedName)' from your workout."
    }
}
