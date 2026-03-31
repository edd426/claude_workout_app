import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct ClaudeLifterApp: App {
    let modelContainer: ModelContainer
    let appState = AppState()
    // Stored as a property so services (sync, anthropic) persist for the app lifetime
    let dependencies: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let container = try ModelContainer(
                for: Exercise.self, ExerciseTag.self, WorkoutSet.self,
                WorkoutExercise.self, TemplateExercise.self, Workout.self,
                WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
                TrainingPreference.self
            )
            modelContainer = container
            dependencies = DependencyContainer(modelContext: container.mainContext)
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
            ContentView(dependencies: dependencies)
                .modelContainer(modelContainer)
                .environment(appState)
                .task {
                    await importExercisesIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { @MainActor in
                    dependencies.syncManager.startMonitoring()
                    await dependencies.syncManager.syncIfNeeded()
                }
            }
        }
    }

    @MainActor
    private func importExercisesIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: "hasImportedExercises") else { return }
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        // Capture context on MainActor before passing to the service
        let context = modelContainer.mainContext
        do {
            try await dependencies.exerciseImportService.importExercises(from: data, into: context)
            UserDefaults.standard.set(true, forKey: "hasImportedExercises")
        } catch {
            // Import failure is non-fatal; will retry next launch since flag is not set
        }
    }
}
