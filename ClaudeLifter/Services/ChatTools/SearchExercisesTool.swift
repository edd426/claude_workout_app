import Foundation

// MARK: - SearchExercisesTool

struct SearchExercisesTool: ClaudeTool {

    static let toolName = "search_exercises"
    static let toolDescription = "Search the exercise library by name. Use this BEFORE creating templates to find the exact exercise names available in the database. Returns up to 10 matching exercises."
    static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Search term (e.g., 'squat', 'bench press', 'deadlift')"
        }
      },
      "required": ["query"]
    }
    """

    func execute(inputJSON: String, context: ToolContext) async throws -> String {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? String else {
            return "Error: missing required parameter query"
        }

        let results = try await context.exerciseRepository.fuzzySearch(query: query)
        let limited = Array(results.prefix(10))

        if limited.isEmpty {
            return "No exercises found matching '\(query)'. Try a simpler search term."
        }

        let names = limited.map { "  - \($0.name)" }.joined(separator: "\n")
        return "Found \(limited.count) exercise(s) matching '\(query)':\n\(names)"
    }
}
