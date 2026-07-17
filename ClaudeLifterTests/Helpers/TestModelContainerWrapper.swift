import SwiftData
@testable import ClaudeLifter

/// Namespace for ai-chat tests that call TestModelContainer.makeTestContainer()
enum TestModelContainer {
    /// Builds from the app's versioned schema — the same single source as the
    /// free-function helper. This wrapper used to carry its own inline type
    /// list that had drifted (it omitted PersonalRecord).
    @MainActor
    static func makeTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema(versionedSchema: CurrentSchema.self),
            configurations: [config]
        )
    }
}
