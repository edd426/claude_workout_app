import Foundation
import Network
import Observation

/// User-facing snapshot of the SyncManager. Derived from its state, not stored.
/// Distinct from `SyncStatus` (which is the per-record `.pending` / `.synced` state on
/// individual models). Priority order (highest first):
///     disabled > offline > syncing > error > synced > pending
/// `disabled` is something the user must fix in Settings; `offline` blocks every other
/// state from being meaningful; in-flight `syncing` matters more than stale errors; a
/// fresh `error` matters more than an older `synced` timestamp.
enum SyncState: Equatable {
    /// Server URL is empty — the iOS app has never been told where to sync to.
    /// This is the silent-no-op state from `syncIfNeeded`'s first guard. The whole
    /// reason this enum exists is to surface this case to the UI.
    case disabled
    /// Server URL is set, but the device has no network connectivity.
    case offline
    /// A sync is currently in flight.
    case syncing
    /// The last sync attempt failed. Carries the error message.
    case error(String)
    /// Sync succeeded at the given timestamp.
    case synced(Date)
    /// Server URL is set, online, idle, no error — but never synced yet.
    case pending
}

@Observable
@MainActor
final class SyncManager {
    var isSyncing = false
    var lastSyncDate: Date?
    var syncError: String?
    var isConnected = true

    /// Derived UI state. See `SyncState` for priority rules.
    var state: SyncState {
        if settings.serverURL.isEmpty { return .disabled }
        if !isConnected { return .offline }
        if isSyncing { return .syncing }
        if let syncError { return .error(syncError) }
        if let lastSyncDate { return .synced(lastSyncDate) }
        return .pending
    }

    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let chatRepository: any ChatMessageRepository
    private let insightRepository: any InsightRepository
    private let preferenceRepository: any TrainingPreferenceRepository
    private let networkService: any NetworkServiceProtocol
    /// Required: pull cannot reconstruct workouts/templates without resolving
    /// exercise references. Optional-with-nil-default is how issue #73 happened —
    /// production omitted it and restores silently skipped everything.
    private let exerciseRepository: any ExerciseRepository
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
        exerciseRepository: any ExerciseRepository,
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
                    try await SyncMapper.applyDTO(dto, to: local, exerciseRepository: exerciseRepository)
                }
            } else {
                let workout = try await SyncMapper.createWorkout(from: dto, exerciseRepository: exerciseRepository)
                try await workoutRepository.save(workout)
            }
        }

        // Merge templates
        for dto in response.templates {
            if let local = try await templateRepository.fetch(id: dto.id) {
                if dto.lastModified > local.lastModified {
                    try await SyncMapper.applyDTO(dto, to: local, exerciseRepository: exerciseRepository)
                }
            } else {
                let template = try await SyncMapper.createTemplate(from: dto, exerciseRepository: exerciseRepository)
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

        // Snapshot lastModified at push time: a record edited while the POST is
        // in flight must stay .pending — the server acknowledged the old payload,
        // not the edit (issue #74). Keyed by (collection, id): a bare-UUID key
        // would let an accepted record in one collection acknowledge a rejected
        // record with the same id in another.
        var pushedModified: [PushKey: Date] = [:]
        for workout in pendingWorkouts { pushedModified[PushKey("workouts", workout.id)] = workout.lastModified }
        for template in pendingTemplates { pushedModified[PushKey("templates", template.id)] = template.lastModified }
        for insight in pendingInsights { pushedModified[PushKey("insights", insight.id)] = insight.lastModified }
        for pref in pendingPrefs { pushedModified[PushKey("preferences", pref.id)] = pref.lastModified }

        let request = SyncPushRequest(
            workouts: pendingWorkouts.map { SyncMapper.toDTO($0) },
            templates: pendingTemplates.map { SyncMapper.toDTO($0) },
            chat: pendingChat.map { SyncMapper.toDTO($0) },
            insights: pendingInsights.map { SyncMapper.toDTO($0) },
            preferences: pendingPrefs.map { SyncMapper.toDTO($0) }
        )

        let response: SyncPushResponse = try await networkService.post(
            endpoint: "/api/sync/push",
            body: request
        )

        guard let results = response.results else {
            // Legacy server without per-record acknowledgement. Marking records
            // synced on faith is the issue-#74 data loss; keeping them .pending
            // is safe — upserts are idempotent, so they re-push next cycle.
            throw SyncError.missingPushAcknowledgement
        }
        let acceptedKeys = Set(
            results.lazy.filter { $0.status == "accepted" }
                .map { PushKey($0.collection, $0.id) }
        )

        // Mark synced only what the server accepted AND what wasn't edited
        // mid-flight. Everything else stays .pending and retries.
        for workout in pendingWorkouts {
            let key = PushKey("workouts", workout.id)
            if acceptedKeys.contains(key) && workout.lastModified == pushedModified[key] {
                workout.syncStatus = .synced
            }
        }
        for template in pendingTemplates {
            let key = PushKey("templates", template.id)
            if acceptedKeys.contains(key) && template.lastModified == pushedModified[key] {
                template.syncStatus = .synced
            }
        }
        for insight in pendingInsights {
            let key = PushKey("insights", insight.id)
            if acceptedKeys.contains(key) && insight.lastModified == pushedModified[key] {
                insight.syncStatus = .synced
            }
        }
        for pref in pendingPrefs {
            let key = PushKey("preferences", pref.id)
            if acceptedKeys.contains(key) && pref.lastModified == pushedModified[key] {
                pref.syncStatus = .synced
            }
        }
        // Chat messages are immutable once created — no mid-flight edit race.
        for message in pendingChat where acceptedKeys.contains(PushKey("chat", message.id)) {
            message.syncStatus = .synced
        }

        // Every submitted record must be acknowledged one way or another. A
        // partial results array leaves the missing records safely .pending,
        // but silence would look like success — surface it.
        let resultKeys = Set(results.map { PushKey($0.collection, $0.id) })
        var submittedKeys = Set(pushedModified.keys)
        for message in pendingChat { submittedKeys.insert(PushKey("chat", message.id)) }
        guard submittedKeys.isSubset(of: resultKeys) else {
            throw SyncError.missingPushAcknowledgement
        }
    }

    /// Identity of a pushed record on the wire: collection + id. Ids are UUIDs
    /// and should never collide across collections, but the response carries the
    /// collection precisely so acknowledgement matching doesn't have to bet on it.
    private struct PushKey: Hashable {
        let collection: String
        let id: UUID
        init(_ collection: String, _ id: UUID) {
            self.collection = collection
            self.id = id
        }
    }
}
