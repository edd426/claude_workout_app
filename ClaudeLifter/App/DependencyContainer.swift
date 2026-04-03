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
    let exerciseImportService: any ExerciseImportServiceProtocol
    let networkService: any NetworkServiceProtocol
    let imageUploadService: any ImageUploadServiceProtocol
    let anthropicService: any AnthropicServiceProtocol
    let insightGenerationService: any InsightGenerationServiceProtocol
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
        self.autoFillService = AutoFillService(workoutRepository: workoutRepo)
        self.exerciseImportService = ExerciseImportService()
        self.networkService = network
        self.imageUploadService = ImageUploadService(networkService: network)

        // Use proxy when serverURL is configured (Phase 2), fall back to direct API key (Phase 1)
        let anthropic: any AnthropicServiceProtocol
        if !settings.serverURL.isEmpty {
            anthropic = ProxiedAnthropicService(networkService: network)
        } else {
            anthropic = AnthropicService(settingsManager: settings)
        }
        self.anthropicService = anthropic
        self.insightGenerationService = InsightGenerationService(
            anthropicService: anthropic,
            workoutRepository: workoutRepo,
            insightRepository: insightRepo
        )

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
