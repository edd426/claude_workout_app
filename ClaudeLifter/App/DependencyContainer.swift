import Foundation
import SwiftData

@MainActor
final class DependencyContainer {
    let workoutRepository: any WorkoutRepository
    let templateRepository: any TemplateRepository
    let exerciseRepository: any ExerciseRepository
    let chatRepository: any ChatMessageRepository
    let preferenceRepository: any TrainingPreferenceRepository
    let insightRepository: any InsightRepository
    let autoFillService: any AutoFillServiceProtocol
    let networkService: any NetworkServiceProtocol
    let syncManager: SyncManager

    init(modelContext: ModelContext) {
        let settings = SettingsManager()

        let workoutRepo = SwiftDataWorkoutRepository(context: modelContext)
        let templateRepo = SwiftDataTemplateRepository(context: modelContext)
        let chatRepo = SwiftDataChatMessageRepository(context: modelContext)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: modelContext)
        let insightRepo = SwiftDataInsightRepository(context: modelContext)
        let network = NetworkService(settings: settings)

        self.workoutRepository = workoutRepo
        self.templateRepository = templateRepo
        self.exerciseRepository = SwiftDataExerciseRepository(context: modelContext)
        self.chatRepository = chatRepo
        self.preferenceRepository = prefRepo
        self.insightRepository = insightRepo
        self.autoFillService = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: modelContext))
        self.networkService = network
        self.syncManager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            settings: settings
        )
    }
}
