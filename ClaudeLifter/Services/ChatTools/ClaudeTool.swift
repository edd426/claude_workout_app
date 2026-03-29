import Foundation

// MARK: - ClaudeTool Protocol

@MainActor
protocol ClaudeTool: Sendable {
    static var toolName: String { get }
    static var toolDescription: String { get }
    /// JSON Schema as a JSON string for Sendable compliance
    static var toolInputSchemaJSON: String { get }

    func execute(inputJSON: String, context: ToolContext) async throws -> String
}

extension ClaudeTool {
    var definition: ToolDefinition {
        guard let data = Self.toolInputSchemaJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ToolDefinition(name: Self.toolName, description: Self.toolDescription, inputSchema: ["type": "object"])
        }
        return ToolDefinition(
            name: Self.toolName,
            description: Self.toolDescription,
            inputSchema: dict
        )
    }
}
