import Foundation

// MARK: - SuggestWeightTool

struct SuggestWeightTool: ClaudeTool {

    static let toolName = "suggest_weight"
    static let toolDescription = "Suggest an appropriate weight for an exercise based on the user's recent history and time since last session. Applies a deload if more than 7 days have passed."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "exercise_name": {
          "type": "string",
          "description": "The name of the exercise to suggest a weight for"
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

        let exercises = try await context.exerciseRepository.search(query: exerciseName)
        guard !exercises.isEmpty else {
            return "No exercise found matching '\(exerciseName)'"
        }

        // (#38 fix) Prefer exact case-insensitive match
        let exercise: Exercise
        if let exact = exercises.first(where: { $0.name.lowercased() == exerciseName.lowercased() }) {
            exercise = exact
        } else if exercises.count == 1 {
            exercise = exercises[0]
        } else {
            let options = exercises.prefix(3).map { $0.name }.joined(separator: ", ")
            return "Multiple exercises match '\(exerciseName)'. Did you mean: \(options)? Please be more specific."
        }

        let recentSets = try await context.workoutRepository.recentSets(for: exercise.id, limit: 10)
        guard !recentSets.isEmpty else {
            return "No history found for '\(exercise.name)'. Start with a moderate weight you're comfortable with."
        }

        // Find the last completed set with a weight
        guard let lastSet = recentSets.first(where: { $0.weight != nil }),
              let lastWeight = lastSet.weight else {
            return "No weight data found for '\(exercise.name)'."
        }

        let unit = lastSet.weightUnit
        let lastReps = lastSet.reps ?? 0

        // Check time since last session using the optimized repository method
        // @needs: WorkoutRepository.lastWorkoutDate(for:) — added by data-models agent
        let daysSinceLast: Int?
        if let lastDate = try? await context.workoutRepository.lastWorkoutDate(for: exercise.id) {
            daysSinceLast = Calendar.current.dateComponents([.day], from: lastDate, to: .now).day
        } else {
            daysSinceLast = nil
        }

        let shouldDeload = (daysSinceLast ?? 0) > 7
        let suggestedWeight: Double
        let reasoning: String

        if shouldDeload {
            suggestedWeight = lastWeight * 0.9
            let days = daysSinceLast ?? 0
            reasoning = "You've been away for \(days) days, so a slight deload (90%) is recommended."
        } else {
            // Suggest same weight or slight increase if they hit all reps last time
            if lastReps >= 10 {
                suggestedWeight = lastWeight * 1.025 // 2.5% increase
                reasoning = "Last time you hit \(lastReps) reps — try a small increase."
            } else {
                suggestedWeight = lastWeight
                reasoning = "Last time: \(lastWeight)\(unit.rawValue) x \(lastReps) reps."
            }
        }

        let rounded = (suggestedWeight * 4).rounded() / 4 // round to nearest 0.25
        return "Suggested weight for \(exercise.name): \(rounded)\(unit.rawValue). \(reasoning)"
    }
}
