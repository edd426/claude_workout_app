import Foundation

// MARK: - LogSetTool

struct LogSetTool: ClaudeTool {

    static let toolName = "log_set"
    static let toolDescription = "Log (complete) an individual set for an exercise in the active workout, optionally overriding weight and reps."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "exercise_name": {
          "type": "string",
          "description": "Name of the exercise in the active workout"
        },
        "set_number": {
          "type": "integer",
          "description": "Which set to log (1-indexed). Defaults to next incomplete set if omitted."
        },
        "weight": {
          "type": "number",
          "description": "Weight lifted (uses pre-filled value if omitted)"
        },
        "reps": {
          "type": "integer",
          "description": "Reps completed (uses pre-filled value if omitted)"
        },
        "weight_unit": {
          "type": "string",
          "enum": ["kg", "lbs"],
          "description": "Weight unit (default: kg)"
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
        guard let we = workout.exercises.first(where: {
            $0.exercise?.name.lowercased() == lowercased
        }) else {
            return "'\(exerciseName)' was not found in your current workout."
        }

        let exerciseDisplayName = we.exercise?.name ?? exerciseName
        let sortedSets = we.sets.sorted { $0.order < $1.order }

        // Determine which set to log
        let targetSet: WorkoutSet
        if let setNumber = json["set_number"] as? Int {
            guard setNumber >= 1, setNumber <= sortedSets.count else {
                return "Invalid set number \(setNumber). \(exerciseDisplayName) only has \(sortedSets.count) sets."
            }
            targetSet = sortedSets[setNumber - 1]
        } else {
            // Find next incomplete set
            guard let nextIncomplete = sortedSets.first(where: { !$0.isCompleted }) else {
                return "All sets for \(exerciseDisplayName) are already complete."
            }
            targetSet = nextIncomplete
        }

        // Override weight/reps/unit if provided
        if let weight = json["weight"] as? Double {
            targetSet.weight = weight
        }
        if let reps = json["reps"] as? Int {
            targetSet.reps = reps
        }
        if let unitStr = json["weight_unit"] as? String {
            targetSet.weightUnit = unitStr.lowercased() == "lbs" ? .lbs : .kg
        }

        // Mark complete
        targetSet.isCompleted = true
        targetSet.completedAt = Date.now
        workout.recordChange()

        try await context.workoutRepository.save(workout)

        // Build result string
        let setIndex = sortedSets.firstIndex(where: { $0.id == targetSet.id }).map { $0 + 1 } ?? 0
        let weightStr: String
        if let w = targetSet.weight {
            let unit = targetSet.weightUnit == .lbs ? "lbs" : "kg"
            weightStr = "\(w) \(unit)"
        } else {
            weightStr = "bodyweight"
        }
        let repsStr = targetSet.reps.map { "\($0) reps" } ?? "? reps"

        return "Logged set \(setIndex) of \(exerciseDisplayName): \(weightStr) \u{00D7} \(repsStr) \u{2713}"
    }
}
