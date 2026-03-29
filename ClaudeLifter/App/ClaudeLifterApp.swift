import SwiftUI
import SwiftData

@main
struct ClaudeLifterApp: App {
    let modelContainer: ModelContainer
    let appState = AppState()

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Exercise.self, ExerciseTag.self, WorkoutSet.self,
                WorkoutExercise.self, TemplateExercise.self, Workout.self,
                WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
                TrainingPreference.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environment(appState)
        }
    }
}
