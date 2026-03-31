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
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let context = modelContainer.mainContext

        if !UserDefaults.standard.bool(forKey: "hasImportedExercises") {
            do {
                try await dependencies.exerciseImportService.importExercises(from: data, into: context)
                UserDefaults.standard.set(true, forKey: "hasImportedExercises")
            } catch {
                // Import failure is non-fatal; will retry next launch since flag is not set
            }
        }

        if !UserDefaults.standard.bool(forKey: "hasPopulatedImageURLs") {
            await populateImageURLsIfNeeded(from: data, context: context)
        }
    }

    @MainActor
    private func populateImageURLsIfNeeded(from data: Data, context: ModelContext) async {
        struct ExerciseImageJSON: Decodable {
            let id: String
            let images: [String]
        }

        guard let jsonArray = try? JSONDecoder().decode([ExerciseImageJSON].self, from: data) else { return }

        let idToFirstImage: [String: String] = jsonArray.reduce(into: [:]) { dict, item in
            if let first = item.images.first {
                dict[item.id] = first
            }
        }

        do {
            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.imageURL == nil && $0.externalId != nil }
            )
            let exercises = try context.fetch(descriptor)
            for exercise in exercises {
                if let exId = exercise.externalId, let firstImage = idToFirstImage[exId] {
                    exercise.imageURL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\(firstImage)"
                }
            }
            if !exercises.isEmpty {
                try context.save()
            }
            UserDefaults.standard.set(true, forKey: "hasPopulatedImageURLs")
        } catch {
            // Non-fatal; will retry next launch
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
