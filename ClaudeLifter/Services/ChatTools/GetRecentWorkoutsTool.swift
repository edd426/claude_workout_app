import Foundation

// MARK: - GetRecentWorkoutsTool

struct GetRecentWorkoutsTool: ClaudeTool {

    static let toolName = "get_recent_workouts"
    static let toolDescription = "Get summaries of recent workout sessions, including the name, date, exercises performed, and total sets."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "limit": {
          "type": "integer",
          "description": "Maximum number of workouts to return (default: 5)"
        }
      },
      "required": []
    }
    """

    func execute(inputJSON: String, context: ToolContext) async throws -> String {
        let limit: Int
        if let data = inputJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let l = json["limit"] as? Int {
            limit = l
        } else {
            limit = 5
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let recentWorkouts = try await context.workoutRepository.fetchByDateRange(from: cutoff, to: Date())
        let workouts = Array(recentWorkouts.prefix(limit))

        if workouts.isEmpty {
            return "No workouts recorded yet."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        var lines = ["Recent workouts:"]
        for workout in workouts {
            let date = formatter.string(from: workout.startedAt)
            let exerciseCount = workout.exercises.count
            let totalSets = workout.exercises.reduce(0) { $0 + $1.sets.count }
            let status = workout.completedAt != nil ? "completed" : "in progress"
            lines.append("  - \(workout.name) on \(date): \(exerciseCount) exercises, \(totalSets) sets (\(status))")
        }
        return lines.joined(separator: "\n")
    }
}
