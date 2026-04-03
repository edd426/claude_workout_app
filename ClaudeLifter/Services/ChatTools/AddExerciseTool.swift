import Foundation

// MARK: - AddExerciseTool

struct AddExerciseTool: ClaudeTool {

    static let toolName = "add_exercise_to_workout"
    static let toolDescription = "Add an exercise to the currently active workout session. Does not modify the underlying template."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "exercise_name": {
          "type": "string",
          "description": "The name of the exercise to add to the active workout"
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

        let exercises = try await context.exerciseRepository.search(query: exerciseName)
        guard !exercises.isEmpty else {
            return "No exercise found matching '\(exerciseName)'"
        }

        // (#38 fix) Prefer exact case-insensitive match over first result
        let exercise: Exercise
        if let exact = exercises.first(where: { $0.name.lowercased() == exerciseName.lowercased() }) {
            exercise = exact
        } else if exercises.count == 1 {
            exercise = exercises[0]
        } else {
            // Multiple ambiguous matches — ask for clarification
            let options = exercises.prefix(3).map { $0.name }.joined(separator: ", ")
            return "Multiple exercises match '\(exerciseName)'. Did you mean: \(options)? Please be more specific."
        }

        // Check not already in the workout
        if workout.exercises.contains(where: { $0.exercise?.id == exercise.id }) {
            return "'\(exercise.name)' is already in your workout."
        }

        let newOrder = workout.exercises.map { $0.order }.max().map { $0 + 1 } ?? 0
        let workoutExercise = WorkoutExercise(order: newOrder, exercise: exercise)
        workout.exercises.append(workoutExercise)
        try await context.workoutRepository.save(workout)

        return "Added '\(exercise.name)' to your workout."
    }
}
