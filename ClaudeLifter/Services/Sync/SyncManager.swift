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
        settings: SettingsManager
    ) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.chatRepository = chatRepository
        self.insightRepository = insightRepository
        self.preferenceRepository = preferenceRepository
        self.networkService = networkService
        self.settings = settings
        self.lastSyncDate = settings.lastSyncTimestamp
    }

    // MARK: - Monitoring

    func startMonitoring() {
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

        // Merge workouts
        let allWorkouts = try await workoutRepository.fetchAll()
        let workoutsById = Dictionary(uniqueKeysWithValues: allWorkouts.map { ($0.id, $0) })
        for dto in response.workouts {
            if let local = workoutsById[dto.id] {
                if dto.lastModified > local.lastModified {
                    SyncMapper.applyDTO(dto, to: local)
                }
            }
            // New workouts from server are not inserted here — full merge requires
            // creating the model graph which is complex; skip for MVP pull-only-updates
        }

        // Merge templates
        let allTemplates = try await templateRepository.fetchAll()
        let templatesById = Dictionary(uniqueKeysWithValues: allTemplates.map { ($0.id, $0) })
        for dto in response.templates {
            if let local = templatesById[dto.id] {
                if dto.lastModified > local.lastModified {
                    SyncMapper.applyDTO(dto, to: local)
                }
            }
        }

        // Merge insights
        let allInsights = try await insightRepository.fetchAll()
        let insightsById = Dictionary(uniqueKeysWithValues: allInsights.map { ($0.id, $0) })
        for dto in response.insights {
            if let local = insightsById[dto.id] {
                if dto.lastModified > local.lastModified {
                    SyncMapper.applyDTO(dto, to: local)
                }
            }
        }

        // Merge preferences
        let allPrefs = try await preferenceRepository.fetchAll()
        let prefsById = Dictionary(uniqueKeysWithValues: allPrefs.map { ($0.id, $0) })
        for dto in response.preferences {
            if let local = prefsById[dto.id] {
                if dto.lastModified > local.lastModified {
                    SyncMapper.applyDTO(dto, to: local)
                }
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
