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
    /// A snapshot push or restore is currently in flight.
    case syncing
    /// The last sync attempt failed. Carries the error message.
    case error(String)
    /// Sync succeeded at the given timestamp.
    case synced(Date)
    /// Server URL is set, online, idle, no error — but never synced yet.
    case pending
}

/// Per-collection outcome of a cloud restore, surfaced in the Settings alert.
struct RestoreSummary: Sendable, Equatable {
    var workouts = 0
    var templates = 0
    var customExercises = 0
    var bodyWeightEntries = 0
    /// Placeholder custom exercises created for exerciseIds that resolved
    /// neither by id nor by name (issue #79 fold-in). Zero on a healthy restore.
    var placeholderExercises = 0
    var revision = 0
}

/// One-way full-state snapshot mirror, phone → Azure (issue #78).
///
/// SwiftData on the phone is authoritative. Every push serializes the COMPLETE
/// local state of the four mirrored types (workouts, templates, custom
/// exercises, body-weight entries) and the server replaces its copy wholesale —
/// deletions propagate by absence, no tombstones, no clock comparison. The
/// cloud exists only for MCP reads and disaster restore (`restoreFromSnapshot`).
/// Per-record `syncStatus` survives purely as the local "is a push due" bit.
@Observable
@MainActor
final class SyncManager {
    var isSyncing = false
    var lastSyncDate: Date?
    /// Server-assigned revision of the last successful push or restore.
    var lastRevision: Int?
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
    /// Needed on both paths: push filters custom exercises out of the library,
    /// restore resolves exercise references (and creates placeholders).
    private let exerciseRepository: any ExerciseRepository
    private let bodyWeightRepository: any BodyWeightRepository
    private let networkService: any NetworkServiceProtocol
    private let settings: SettingsManager

    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.claudelifter.sync.monitor")

    init(
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository,
        bodyWeightRepository: any BodyWeightRepository,
        networkService: any NetworkServiceProtocol,
        settings: SettingsManager
    ) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
        self.bodyWeightRepository = bodyWeightRepository
        self.networkService = networkService
        self.settings = settings
        self.lastSyncDate = settings.lastSyncTimestamp
        self.lastRevision = settings.lastSyncRevision
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
            // Any record turning .pending means a snapshot push is due. The
            // snapshot itself is always FULL state — pending is only the trigger.
            guard try await hasPendingChanges() else { return }
            try await pushSnapshot()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func hasPendingChanges() async throws -> Bool {
        if try await !workoutRepository.fetchPending().isEmpty { return true }
        if try await !templateRepository.fetchPending().isEmpty { return true }
        if try await !bodyWeightRepository.fetchPending().isEmpty { return true }
        return false
    }

    // MARK: - Push

    /// Serialize the complete local state of the four mirrored types and POST
    /// it as one snapshot. On 200, mark records `.synced` and persist the
    /// server revision. On any failure, everything stays `.pending` and the
    /// next trigger retries — the operation is idempotent by design.
    func pushSnapshot() async throws {
        let workouts = try await workoutRepository.fetchAll()
        let templates = try await templateRepository.fetchAll()
        let customExercises = try await exerciseRepository.fetchAll().filter(\.isCustom)
        let bodyWeightEntries = try await bodyWeightRepository.fetchAll()

        // Snapshot lastModified at serialization time: a record edited while
        // the POST is in flight must stay .pending — the server received the
        // old payload, not the edit (issue #74's guarantee, kept in v2).
        let workoutModified = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.lastModified) })
        let templateModified = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0.lastModified) })
        let entryModified = Dictionary(uniqueKeysWithValues: bodyWeightEntries.map { ($0.id, $0.lastModified) })

        // ALWAYS all four collections, even when empty — the server rejects a
        // missing key, and an empty array legitimately means "wipe that type".
        let request = SnapshotPushRequest(
            snapshot: SyncSnapshot(
                workouts: workouts.map { SyncMapper.toDTO($0) },
                templates: templates.map { SyncMapper.toDTO($0) },
                customExercises: customExercises.map { SyncMapper.toDTO($0) },
                bodyWeightEntries: bodyWeightEntries.map { SyncMapper.toDTO($0) }
            )
        )

        let response = try await networkService.pushSnapshot(request)

        for workout in workouts where workout.lastModified == workoutModified[workout.id] {
            workout.syncStatus = .synced
        }
        for template in templates where template.lastModified == templateModified[template.id] {
            template.syncStatus = .synced
        }
        for entry in bodyWeightEntries where entry.lastModified == entryModified[entry.id] {
            entry.syncStatus = .synced
        }

        recordSuccess(revision: response.revision, serverTime: response.serverTime)
    }

    // MARK: - Restore

    /// Disaster recovery: fetch the cloud mirror and REPLACE local data for the
    /// four mirrored types. Never touches chat history, insights, preferences,
    /// or the bundled exercise library. Destructive — callers must confirm with
    /// the user first (Settings does).
    func restoreFromSnapshot() async throws -> RestoreSummary {
        guard !isSyncing else { throw SyncError.syncInProgress }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let response = try await networkService.fetchSnapshot()

            // A fresh mirror (never pushed to) reads as revision 0 with four
            // empty arrays. Wiping local data with that would be data loss
            // dressed up as a restore — refuse.
            guard response.revision > 0 else { throw SyncError.emptyMirror }

            let snapshot = response.snapshot
            var summary = RestoreSummary()
            summary.revision = response.revision

            // 1. Wipe the four mirrored types.
            for workout in try await workoutRepository.fetchAll() {
                try await workoutRepository.delete(workout)
            }
            for template in try await templateRepository.fetchAll() {
                try await templateRepository.delete(template)
            }
            for exercise in try await exerciseRepository.fetchAll() where exercise.isCustom {
                try await exerciseRepository.delete(exercise)
            }
            for entry in try await bodyWeightRepository.fetchAll() {
                try await bodyWeightRepository.delete(entry)
            }

            // 2. Custom exercises FIRST so template/workout references resolve.
            //    Insert the exercise, then attach tags (relationship objects
            //    must attach to a managed parent).
            for dto in snapshot.customExercises {
                let exercise = SyncMapper.createExercise(from: dto)
                try await exerciseRepository.save(exercise)
                if !dto.tags.isEmpty {
                    exercise.tags = dto.tags.map {
                        ExerciseTag(category: $0.category, value: $0.value)
                    }
                    try await exerciseRepository.save(exercise)
                }
                summary.customExercises += 1
            }

            // 3. Placeholders for exercise references that resolve neither by
            //    id nor by name — the sets must survive, not silently drop.
            summary.placeholderExercises = try await createPlaceholderExercises(for: snapshot)

            // 4. Templates and workouts (factories mark them .synced — local
            //    state now equals the mirror, no re-push due).
            for dto in snapshot.templates {
                let template = try await SyncMapper.createTemplate(
                    from: dto, exerciseRepository: exerciseRepository
                )
                try await templateRepository.save(template)
                summary.templates += 1
            }
            for dto in snapshot.workouts {
                let workout = try await SyncMapper.createWorkout(
                    from: dto, exerciseRepository: exerciseRepository
                )
                try await workoutRepository.save(workout)
                summary.workouts += 1
            }

            // 5. Body-weight entries.
            for dto in snapshot.bodyWeightEntries {
                try await bodyWeightRepository.save(SyncMapper.createBodyWeightEntry(from: dto))
                summary.bodyWeightEntries += 1
            }

            recordSuccess(revision: response.revision, serverTime: response.serverTime)
            return summary
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }

    /// For every exercise reference in the snapshot that resolves neither by id
    /// nor by fuzzy name (SyncMapper's resolution order), insert a placeholder
    /// custom exercise carrying the referenced id so the workout's sets survive.
    private func createPlaceholderExercises(for snapshot: SyncSnapshot) async throws -> Int {
        var references: [(id: UUID, name: String?)] = []
        for template in snapshot.templates {
            for te in template.exercises {
                references.append((te.exerciseId, te.exerciseName))
            }
        }
        for workout in snapshot.workouts {
            for we in workout.exercises {
                references.append((we.exerciseId, we.exerciseName))
            }
        }

        var created = 0
        var seen = Set<UUID>()
        for reference in references where !seen.contains(reference.id) {
            seen.insert(reference.id)
            if try await exerciseRepository.fetch(id: reference.id) != nil { continue }
            if let name = reference.name,
               try await !exerciseRepository.fuzzySearch(query: name).isEmpty {
                continue
            }
            let placeholder = Exercise(
                id: reference.id,
                name: "Unknown exercise (restored)",
                isCustom: true
            )
            try await exerciseRepository.save(placeholder)
            created += 1
        }
        return created
    }

    // MARK: - Bookkeeping

    private func recordSuccess(revision: Int, serverTime: Date) {
        lastSyncDate = serverTime
        lastRevision = revision
        settings.lastSyncTimestamp = serverTime
        settings.lastSyncRevision = revision
    }
}
