import Foundation
import SwiftData
import SwiftUI

@MainActor
final class DependencyContainer {
    let workoutRepository: any WorkoutRepository
    let templateRepository: any TemplateRepository
    let baselineRepository: any TemplateBaselineRepository
    let exerciseRepository: any ExerciseRepository
    let chatRepository: any ChatMessageRepository
    let preferenceRepository: any TrainingPreferenceRepository
    let insightRepository: any InsightRepository
    let autoFillService: any AutoFillServiceProtocol
    let prDetectionService: any PRDetectionServiceProtocol
    let exerciseImportService: any ExerciseImportServiceProtocol
    let networkService: any NetworkServiceProtocol
    let imageUploadService: any ImageUploadServiceProtocol
    let anthropicService: any AnthropicServiceProtocol
    let insightGenerationService: any InsightGenerationServiceProtocol
    let backupService: any BackupServiceProtocol
    let bodyWeightRepository: any BodyWeightRepository
    let exerciseReportRepository: any ExerciseReportRepository
    /// Waist and other circumferences (#165).
    let bodyMeasurementRepository: any BodyMeasurementRepository
    /// User-defined medications (#164). Archive, don't delete.
    let medicationRepository: any MedicationRepository
    /// Logged doses (#164).
    let medicationDoseRepository: any MedicationDoseRepository
    /// "If the machine is taken" substitutes on template exercises.
    let exerciseAlternativeRepository: any ExerciseAlternativeRepository
    /// Downloads exercise photos that live in blob storage (#170) into the
    /// local cache `LocalPhotoStorage` reads. SyncManager runs it on every
    /// sync and after an approval; a view may also call it.
    let exercisePhotoFetcher: any ExercisePhotoFetching
    /// Report photos kept on the phone until they upload (#141).
    let reportPhotoStore: any ReportPhotoStoring
    let inboxApplier: InboxApplier
    let healthKitService: any HealthKitServiceProtocol
    /// Shared rest-timer tick source — one instance for the app instead of
    /// per-view instantiation (issue #77).
    let restTimerService: any RestTimerServiceProtocol
    /// Schedules the rest-complete local notification so the chime fires
    /// while the phone is locked (issue #77).
    let notificationScheduler: any NotificationScheduling
    let syncManager: SyncManager
    /// Exposed so ViewModels (ChatViewModel especially) can read the user's
    /// selected AI model. Previously this was built inside init() but not
    /// stored on the container, so ChatViewModel was constructed with
    /// settings=nil and fell back to a hardcoded Haiku default — the user's
    /// Opus / Sonnet choice was silently ignored for every chat request.
    let settings: SettingsManager

    init(modelContext: ModelContext) {
        let settings = SettingsManager()
        self.settings = settings

        let workoutRepo = SwiftDataWorkoutRepository(context: modelContext)
        let templateRepo = SwiftDataTemplateRepository(context: modelContext)
        let baselineRepo = SwiftDataTemplateBaselineRepository(context: modelContext)
        let chatRepo = SwiftDataChatMessageRepository(context: modelContext)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: modelContext)
        let insightRepo = SwiftDataInsightRepository(context: modelContext)
        // A deletion leaves no `.pending` row behind, so these repositories
        // set the durable snapshot trigger themselves; otherwise a deleted
        // dose would linger in the mirror until some unrelated change.
        let measurementRepo = SwiftDataBodyMeasurementRepository(
            context: modelContext,
            onDeletion: { settings.markSnapshotDirty() }
        )
        let medicationRepo = SwiftDataMedicationRepository(context: modelContext)
        let doseRepo = SwiftDataMedicationDoseRepository(
            context: modelContext,
            onDeletion: { settings.markSnapshotDirty() }
        )
        let alternativeRepo = SwiftDataExerciseAlternativeRepository(
            context: modelContext,
            onDeletion: { settings.markSnapshotDirty() }
        )
        self.bodyMeasurementRepository = measurementRepo
        self.medicationRepository = medicationRepo
        self.medicationDoseRepository = doseRepo
        self.exerciseAlternativeRepository = alternativeRepo
        // Custom exercises have no per-record syncStatus, so their only
        // "a push is due" signal is this callback (#104).
        let exerciseRepo = SwiftDataExerciseRepository(
            context: modelContext,
            onCustomExerciseChanged: { settings.markSnapshotDirty() }
        )
        let network = NetworkService(settings: settings)

        self.workoutRepository = workoutRepo
        self.templateRepository = templateRepo
        self.baselineRepository = baselineRepo
        self.exerciseRepository = exerciseRepo
        self.chatRepository = chatRepo
        self.preferenceRepository = prefRepo
        self.insightRepository = insightRepo
        self.autoFillService = AutoFillService(workoutRepository: workoutRepo)
        let personalRecordRepo = SwiftDataPersonalRecordRepository(context: modelContext)
        self.prDetectionService = PRDetectionService(prRepository: personalRecordRepo)
        self.exerciseImportService = ExerciseImportService()
        self.backupService = BackupService(
            modelContext: modelContext,
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            exerciseRepository: exerciseRepo,
            preferenceRepository: prefRepo,
            bodyMeasurementRepository: measurementRepo,
            medicationRepository: medicationRepo,
            medicationDoseRepository: doseRepo,
            exerciseAlternativeRepository: alternativeRepo,
            settings: settings
        )
        self.networkService = network
        let imageUploadService = ImageUploadService(networkService: network)
        self.imageUploadService = imageUploadService
        let exercisePhotoFetcher = ExercisePhotoDownloader(
            exerciseRepository: exerciseRepo,
            imageService: imageUploadService
        )
        self.exercisePhotoFetcher = exercisePhotoFetcher
        let bodyWeightRepo = SwiftDataBodyWeightRepository(context: modelContext)
        self.bodyWeightRepository = bodyWeightRepo
        let reportRepo = SwiftDataExerciseReportRepository(context: modelContext)
        self.exerciseReportRepository = reportRepo
        let reportPhotoStore = LocalReportPhotoStore()
        self.reportPhotoStore = reportPhotoStore
        let inboxApplier = InboxApplier(
            templateRepository: templateRepo,
            exerciseRepository: exerciseRepo,
            reportRepository: reportRepo,
            alternativeRepository: alternativeRepo
        )
        self.inboxApplier = inboxApplier
        self.healthKitService = HealthKitService()
        self.restTimerService = RestTimerService()
        self.notificationScheduler = UserNotificationScheduler()

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
            insightRepository: insightRepo,
            settings: settings
        )

        self.syncManager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            exerciseRepository: exerciseRepo,
            bodyWeightRepository: bodyWeightRepo,
            exerciseReportRepository: reportRepo,
            bodyMeasurementRepository: measurementRepo,
            medicationRepository: medicationRepo,
            medicationDoseRepository: doseRepo,
            exerciseAlternativeRepository: alternativeRepo,
            networkService: network,
            settings: settings,
            inboxApplier: inboxApplier,
            reportPhotoUploader: ReportPhotoUploader(
                reportRepository: reportRepo,
                photoStore: reportPhotoStore,
                imageUploadService: imageUploadService
            ),
            exercisePhotoFetcher: exercisePhotoFetcher
        )
    }
}

private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue: DependencyContainer? = nil
}

extension EnvironmentValues {
    var dependencies: DependencyContainer? {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}
