import Foundation

// MARK: - SetExerciseTargetsTool

struct SetExerciseTargetsTool: ClaudeTool {

    static let toolName = "set_exercise_targets"
    static let toolDescription = "Set or edit the number of sets, target reps, and target weight for an exercise in the active workout session."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "exercise_name": {
          "type": "string",
          "description": "Name of the exercise in the active workout"
        },
        "sets": {
          "type": "integer",
          "description": "Target number of sets"
        },
        "reps": {
          "type": "integer",
          "description": "Target reps per set"
        },
        "weight": {
          "type": "number",
          "description": "Target weight per set"
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

        // Adjust set count if requested
        if let targetSets = json["sets"] as? Int, targetSets > 0 {
            let sorted = we.sets.sorted { $0.order < $1.order }
            let currentCount = sorted.count

            if targetSets > currentCount {
                // Add sets, carrying forward weight/reps from last existing set
                let lastSet = sorted.last
                let templateWeight = lastSet?.weight
                let templateReps = lastSet?.reps
                let templateUnit = lastSet?.weightUnit ?? .kg

                for i in currentCount..<targetSets {
                    let newSet = WorkoutSet(
                        order: i,
                        weight: templateWeight,
                        weightUnit: templateUnit,
                        reps: templateReps
                    )
                    we.sets.append(newSet)
                }
            } else if targetSets < currentCount {
                // Remove sets from the end (highest order first)
                let toRemove = sorted.suffix(currentCount - targetSets)
                we.sets.removeAll { s in toRemove.contains(where: { $0.id == s.id }) }
            }
        }

        // Update reps on all sets if provided
        if let reps = json["reps"] as? Int {
            for s in we.sets {
                s.reps = reps
            }
        }

        // Update weight on all sets if provided
        if let weight = json["weight"] as? Double {
            for s in we.sets {
                s.weight = weight
            }
        }

        // Update weight unit on all sets if provided
        if let unitStr = json["weight_unit"] as? String {
            let unit: WeightUnit = unitStr.lowercased() == "lbs" ? .lbs : .kg
            for s in we.sets {
                s.weightUnit = unit
            }
        }

        try await context.workoutRepository.save(workout)

        // Build summary
        let sortedSets = we.sets.sorted { $0.order < $1.order }
        let setCount = sortedSets.count
        let repsDisplay = sortedSets.first?.reps.map { "\($0) reps" } ?? "? reps"
        let weightDisplay: String
        if let w = sortedSets.first?.weight {
            let unit = sortedSets.first?.weightUnit ?? .kg
            weightDisplay = " @ \(w) \(unit == .lbs ? "lbs" : "kg")"
        } else {
            weightDisplay = ""
        }

        return "Updated \(exerciseDisplayName): \(setCount) sets \u{00D7} \(repsDisplay)\(weightDisplay)"
    }
}
