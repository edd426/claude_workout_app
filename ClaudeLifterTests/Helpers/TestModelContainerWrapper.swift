import SwiftData
@testable import ClaudeLifter

/// Namespace for ai-chat tests that call TestModelContainer.makeTestContainer()
enum TestModelContainer {
    @MainActor
    static func makeTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Exercise.self, ExerciseTag.self, WorkoutSet.self,
            WorkoutExercise.self, TemplateExercise.self, Workout.self,
            WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
            TrainingPreference.self,
            configurations: config
        )
    }
}
