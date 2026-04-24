import Foundation

// MARK: - EndWorkoutTool

/// Lets Coach finish or discard the active workout — and, on user request,
/// clean up every stale in-progress workout left behind by force-quits or
/// previous exits. Before this tool existed Coach would (correctly) tell
/// the user it had no ability to close sessions, leaving users stranded
/// when their history filled with "in progress" ghosts.
struct EndWorkoutTool: ClaudeTool {

    static let toolName = "end_workout"
    static let toolDescription = """
    End the currently active workout, or clean up stale in-progress workouts \
    from history. Use action="finish" to mark the active workout complete (only \
    valid if at least one set has been logged), action="discard" to throw away \
    the active workout without recording it, or action="cleanup_stale" to delete \
    every in-progress (`completedAt == null`) workout including the active one. \
    The last option is how the user cleans out duplicates that piled up from \
    previous sessions.
    """
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "action": {
          "type": "string",
          "enum": ["finish", "discard", "cleanup_stale"],
          "description": "finish = complete the active workout; discard = throw it away; cleanup_stale = delete all in-progress workouts"
        }
      },
      "required": ["action"]
    }
    """

    func execute(inputJSON: String, context: ToolContext) async throws -> String {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            return "Error: missing required parameter 'action' (finish | discard | cleanup_stale)."
        }

        switch action {
        case "finish":
            return try await finishActive(context: context)
        case "discard":
            return try await discardActive(context: context)
        case "cleanup_stale":
            return try await cleanupStale(context: context)
        default:
            return "Error: unknown action '\(action)'. Must be finish, discard, or cleanup_stale."
        }
    }

    private func finishActive(context: ToolContext) async throws -> String {
        guard let workout = context.activeWorkout else {
            return "No active workout to finish."
        }
        let hasCompleted = workout.exercises
            .flatMap(\.sets)
            .contains(where: { $0.isCompleted })
        guard hasCompleted else {
            return "Cannot finish '\(workout.name)' — no sets are marked complete. Log at least one set first, or use action=\"discard\" instead."
        }
        workout.completedAt = .now
        workout.recordChange()
        try await context.workoutRepository.save(workout)
        let setCount = workout.exercises.flatMap(\.sets).filter(\.isCompleted).count
        return "Finished '\(workout.name)' — \(setCount) completed sets across \(workout.exercises.count) exercise(s) saved to history."
    }

    private func discardActive(context: ToolContext) async throws -> String {
        guard let workout = context.activeWorkout else {
            return "No active workout to discard."
        }
        let name = workout.name
        try await context.workoutRepository.delete(workout)
        return "Discarded '\(name)'. Nothing was recorded to history."
    }

    private func cleanupStale(context: ToolContext) async throws -> String {
        let all = try await context.workoutRepository.fetchAll()
        let stale = all.filter { $0.completedAt == nil }
        guard !stale.isEmpty else {
            return "No stale workouts found — history is clean."
        }
        var deleted = 0
        for workout in stale {
            do {
                try await context.workoutRepository.delete(workout)
                deleted += 1
            } catch {
                // Keep going; report the partial count.
                continue
            }
        }
        let names = stale.prefix(5).map { "'\($0.name)'" }.joined(separator: ", ")
        let suffix = stale.count > 5 ? " (and \(stale.count - 5) more)" : ""
        return "Deleted \(deleted) stale in-progress workout(s): \(names)\(suffix). Your history now only contains finished sessions."
    }
}
