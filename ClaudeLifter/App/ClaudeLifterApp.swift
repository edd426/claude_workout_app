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

    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
    private let shouldSeedTestData = ProcessInfo.processInfo.arguments.contains("-seedTestData")

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        do {
            let container: ModelContainer
            if isUITesting {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(
                    for: Exercise.self, ExerciseTag.self, WorkoutSet.self,
                    WorkoutExercise.self, TemplateExercise.self, Workout.self,
                    WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
                    TrainingPreference.self, PersonalRecord.self,
                    configurations: config
                )
            } else {
                container = try ModelContainer(
                    for: Exercise.self, ExerciseTag.self, WorkoutSet.self,
                    WorkoutExercise.self, TemplateExercise.self, Workout.self,
                    WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
                    TrainingPreference.self, PersonalRecord.self
                )
            }
            modelContainer = container
            dependencies = DependencyContainer(modelContext: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        if !isUITesting {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: "com.claudelifter.sync",
                using: nil
            ) { _ in }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
                .modelContainer(modelContainer)
                .environment(appState)
                .task {
                    if isUITesting {
                        if shouldSeedTestData {
                            await seedTestData(context: modelContainer.mainContext)
                        }
                    } else {
                        await importExercisesIfNeeded()
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !isUITesting else { return }
            if newPhase == .active {
                Task { @MainActor in
                    dependencies.syncManager.startMonitoring()
                    await dependencies.syncManager.syncIfNeeded()
                    if dependencies.insightGenerationService.shouldGenerateInsights() {
                        try? await dependencies.insightGenerationService.generateInsights()
                    }
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

    @MainActor
    private func seedTestData(context: ModelContext) async {
        // Insert test exercises
        let benchPress = Exercise(
            name: "Bench Press",
            mechanic: "compound",
            equipment: "barbell",
            primaryMuscles: ["chest"],
            secondaryMuscles: ["triceps", "shoulders"],
            isCustom: false
        )
        let squat = Exercise(
            name: "Barbell Squat",
            mechanic: "compound",
            equipment: "barbell",
            primaryMuscles: ["quadriceps"],
            secondaryMuscles: ["glutes", "hamstrings"],
            isCustom: false
        )
        let ohp = Exercise(
            name: "Overhead Press",
            mechanic: "compound",
            equipment: "barbell",
            primaryMuscles: ["shoulders"],
            secondaryMuscles: ["triceps"],
            isCustom: false
        )
        context.insert(benchPress)
        context.insert(squat)
        context.insert(ohp)

        // Insert test template: Push Day
        let pushDay = WorkoutTemplate(name: "Push Day")
        context.insert(pushDay)

        let te1 = TemplateExercise(order: 0, exercise: benchPress, defaultSets: 3, defaultReps: 8)
        let te2 = TemplateExercise(order: 1, exercise: ohp, defaultSets: 3, defaultReps: 10)
        pushDay.exercises.append(te1)
        pushDay.exercises.append(te2)
        context.insert(te1)
        context.insert(te2)

        // Insert completed workout from yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let completedWorkout = Workout(name: "Push Day", startedAt: yesterday)
        completedWorkout.completedAt = yesterday.addingTimeInterval(3600)
        completedWorkout.templateId = pushDay.id
        context.insert(completedWorkout)

        let we = WorkoutExercise(order: 0, exercise: benchPress, restSeconds: 90)
        completedWorkout.exercises.append(we)
        context.insert(we)

        let set1 = WorkoutSet(order: 0, weight: 80, weightUnit: .kg, reps: 8)
        set1.isCompleted = true
        set1.completedAt = yesterday.addingTimeInterval(300)
        we.sets.append(set1)
        context.insert(set1)

        try? context.save()
    }
}
