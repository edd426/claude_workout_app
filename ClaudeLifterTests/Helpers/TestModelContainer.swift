import SwiftData
@testable import ClaudeLifter

@MainActor
func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Exercise.self, ExerciseTag.self, WorkoutSet.self,
        WorkoutExercise.self, TemplateExercise.self, Workout.self,
        WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
        TrainingPreference.self, PersonalRecord.self,
        configurations: config
    )
}
