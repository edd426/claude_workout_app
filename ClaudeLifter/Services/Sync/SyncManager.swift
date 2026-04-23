import Foundation
import Network
import Observation

@Observable
@MainActor
final class SyncManager {
    var isSyncing = false
    var lastSyncDate: Date?
    var syncError: String?
    var isConnected = true

    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let chatRepository: any ChatMessageRepository
    private let insightRepository: any InsightRepository
    private let preferenceRepository: any TrainingPreferenceRepository
    private let networkService: any NetworkServiceProtocol
    private let exerciseRepository: (any ExerciseRepository)?
    private let settings: SettingsManager

    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.claudelifter.sync.monitor")

    init(
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        chatRepository: any ChatMessageRepository,
        insightRepository: any InsightRepository,
        preferenceRepository: any TrainingPreferenceRepository,
        networkService: any NetworkServiceProtocol,
        exerciseRepository: (any ExerciseRepository)? = nil,
        settings: SettingsManager
    ) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.chatRepository = chatRepository
        self.insightRepository = insightRepository
        self.preferenceRepository = preferenceRepository
        self.networkService = networkService
        self.exerciseRepository = exerciseRepository
        self.settings = settings
        self.lastSyncDate = settings.lastSyncTimestamp
    }

    // MARK: - Monitoring

    func startMonitoring() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - Sync orchestration

    func syncIfNeeded() async {
        guard !settings.serverURL.isEmpty else { return }
        guard isConnected else { return }
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            try await pull()
            try await push()
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Pull

    func pull() async throws {
        let request = SyncPullRequest(
            lastSyncTimestamp: settings.lastSyncTimestamp,
            collections: ["workouts", "templates", "chat", "insights", "preferences"]
        )

        let response: SyncPullResponse = try await networkService.post(
            endpoint: "/api/sync/pull",
            body: request
        )

        try await mergePullResponse(response)

        lastSyncDate = response.serverTimestamp
        settings.lastSyncTimestamp = response.serverTimestamp
    }

    private func mergePullResponse(_ response: SyncPullResponse) async throws {
        // Last-write-wins by lastModified date
        // Uses per-ID lookups instead of fetchAll() to avoid loading entire tables

        // Merge workouts
        for dto in response.workouts {
            if let local = try await workoutRepository.fetch(id: dto.id) {
                if dto.lastModified > local.lastModified {
                    if let exerciseRepo = exerciseRepository {
                        try await SyncMapper.applyDTO(dto, to: local, exerciseRepository: exerciseRepo)
                    } else {
                        SyncMapper.applyDTO(dto, to: local)
                    }
                }
            } else if let exerciseRepo = exerciseRepository {
                let workout = try await SyncMapper.createWorkout(from: dto, exerciseRepository: exerciseRepo)
                try await workoutRepository.save(workout)
            }
        }

        // Merge templates
        for dto in response.templates {
            if let local = try await templateRepository.fetch(id: dto.id) {
                if dto.lastModified > local.lastModified {
                    if let exerciseRepo = exerciseRepository {
                        try await SyncMapper.applyDTO(dto, to: local, exerciseRepository: exerciseRepo)
                    } else {
                        SyncMapper.applyDTO(dto, to: local)
                    }
                }
            } else if let exerciseRepo = exerciseRepository {
                let template = try await SyncMapper.createTemplate(from: dto, exerciseRepository: exerciseRepo)
                try await templateRepository.save(template)
            }
        }

        // Merge insights
        for dto in response.insights {
            if let local = try await insightRepository.fetch(id: dto.id) {
                if dto.lastModified > local.lastModified {
                    SyncMapper.applyDTO(dto, to: local)
                }
            } else {
                let insight = SyncMapper.createInsight(from: dto)
                try await insightRepository.save(insight)
            }
        }

        // Merge preferences
        for dto in response.preferences {
            if let local = try await preferenceRepository.fetch(id: dto.id) {
                if dto.lastModified > local.lastModified {
                    SyncMapper.applyDTO(dto, to: local)
                }
            } else {
                try await preferenceRepository.upsert(
                    key: dto.key,
                    value: dto.value,
                    source: dto.source
                )
            }
        }
    }

    // MARK: - Push

    func push() async throws {
        let pendingWorkouts = try await workoutRepository.fetchPending()
        let pendingTemplates = try await templateRepository.fetchPending()
        let pendingChat = try await chatRepository.fetchPending()
        let pendingInsights = try await insightRepository.fetchPending()
        let pendingPrefs = try await preferenceRepository.fetchPending()

        let hasAnything = !pendingWorkouts.isEmpty || !pendingTemplates.isEmpty ||
            !pendingChat.isEmpty || !pendingInsights.isEmpty || !pendingPrefs.isEmpty

        guard hasAnything else { return }

        let request = SyncPushRequest(
            workouts: pendingWorkouts.map { SyncMapper.toDTO($0) },
            templates: pendingTemplates.map { SyncMapper.toDTO($0) },
            chat: pendingChat.map { SyncMapper.toDTO($0) },
            insights: pendingInsights.map { SyncMapper.toDTO($0) },
            preferences: pendingPrefs.map { SyncMapper.toDTO($0) }
        )

        let _: SyncPushResponse = try await networkService.post(
            endpoint: "/api/sync/push",
            body: request
        )

        // Mark all as synced
        for workout in pendingWorkouts {
            workout.syncStatus = .synced
        }
        for template in pendingTemplates {
            template.syncStatus = .synced
        }
        for message in pendingChat {
            message.syncStatus = .synced
        }
        for insight in pendingInsights {
            insight.syncStatus = .synced
        }
        for pref in pendingPrefs {
            pref.syncStatus = .synced
        }
    }
}
