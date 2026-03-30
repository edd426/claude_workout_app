import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct ClaudeLifterApp: App {
    let modelContainer: ModelContainer
    let appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

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

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.claudelifter.sync",
            using: nil
        ) { _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environment(appState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { @MainActor in
                    let container = DependencyContainer(modelContext: modelContainer.mainContext)
                    container.syncManager.startMonitoring()
                    await container.syncManager.syncIfNeeded()
                }
            }
        }
    }
}
