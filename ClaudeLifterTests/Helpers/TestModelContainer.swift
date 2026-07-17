import SwiftData
@testable import ClaudeLifter

@MainActor
func makeTestContainer() throws -> ModelContainer {
    // Built from the app's versioned schema — the single source of truth
    // (AppSchema.swift). Never list model types inline here: the old inline
    // list silently diverged from its sibling helper (one had PersonalRecord,
    // one didn't), which is exactly the trap issue #72 exists to close.
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Schema(versionedSchema: CurrentSchema.self),
        configurations: [config]
    )
}
