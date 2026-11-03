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

/// A user's verdict on one awaiting-approval inbox operation (#153).
struct InboxDecision: Equatable, Sendable {
    enum Verdict: Equatable, Sendable {
        case approve
        case decline
    }

    let operation: InboxOperationDTO
    let verdict: Verdict
}

@MainActor
protocol InboxApprovalManaging: AnyObject {
    func fetchPendingApprovals() async throws -> [InboxOperationDTO]
    func approve(_ operation: InboxOperationDTO) async throws
    func decline(_ operation: InboxOperationDTO) async throws
    /// Applies every decision locally, acknowledges them to the server in ONE
    /// request, and pushes ONE snapshot if anything was applied. N decisions
    /// used to mean N serial syncs (#153).
    func decide(_ decisions: [InboxDecision]) async throws
}

/// Per-collection outcome of a cloud restore, surfaced in the Settings alert.
struct RestoreSummary: Sendable, Equatable {
    var workouts = 0
    var templates = 0
    var customExercises = 0
    var bodyWeightEntries = 0
    var exerciseReports = 0
    /// Bundled exercises whose note/photo was reapplied from the mirror (#140).
    var exerciseOverlays = 0
    /// schemaVersion 5. All four stay 0 when the mirror predates v5 — local
    /// data for those types is then left untouched, not wiped.
    var bodyMeasurements = 0
    var medications = 0
    var medicationDoses = 0
    var exerciseAlternatives = 0
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
final class SyncManager: InboxApprovalManaging {
    var isSyncing = false
    var lastSyncDate: Date?
    /// Server-assigned revision of the last successful push or restore.
    var lastRevision: Int?
    var syncError: String?
    var isConnected = true
    private(set) var pendingApprovals: [InboxOperationDTO] = []

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
    private let exerciseReportRepository: any ExerciseReportRepository
    // schemaVersion 5 collections. Required, never optional: a missing
    // repository would push an empty array, which a v5 server reads as
    // "wipe this collection".
    private let bodyMeasurementRepository: any BodyMeasurementRepository
    private let medicationRepository: any MedicationRepository
    private let medicationDoseRepository: any MedicationDoseRepository
    private let exerciseAlternativeRepository: any ExerciseAlternativeRepository
    private let networkService: any NetworkServiceProtocol
    private let settings: SettingsManager
    private let inboxApplier: InboxApplier
    /// Uploads report photos kept offline (#141). Optional so existing
    /// construction sites keep compiling; nil means photos never upload.
    private let reportPhotoUploader: (any ReportPhotoUploading)?

    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.claudelifter.sync.monitor")

    init(
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository,
        bodyWeightRepository: any BodyWeightRepository,
        exerciseReportRepository: any ExerciseReportRepository,
        bodyMeasurementRepository: any BodyMeasurementRepository,
        medicationRepository: any MedicationRepository,
        medicationDoseRepository: any MedicationDoseRepository,
        exerciseAlternativeRepository: any ExerciseAlternativeRepository,
        networkService: any NetworkServiceProtocol,
        settings: SettingsManager,
        inboxApplier: InboxApplier,
        reportPhotoUploader: (any ReportPhotoUploading)? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
        self.bodyWeightRepository = bodyWeightRepository
        self.exerciseReportRepository = exerciseReportRepository
        self.bodyMeasurementRepository = bodyMeasurementRepository
        self.medicationRepository = medicationRepository
        self.medicationDoseRepository = medicationDoseRepository
        self.exerciseAlternativeRepository = exerciseAlternativeRepository
        self.networkService = networkService
        self.settings = settings
        self.inboxApplier = inboxApplier
        self.reportPhotoUploader = reportPhotoUploader
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
            var deferredInboxAckError: Error?
            // Inbox work must run before the pending guard. An idle phone has
            // no pending local records until this step creates one.
            let inbox = try await networkService.fetchInbox(status: .pending)
            if !inbox.operations.isEmpty {
                let results = await inboxApplier.process(inbox.operations)
                if results.contains(where: { $0.status == .applied }) {
                    settings.markSnapshotDirty()
                }
                let request = InboxAckRequest(results: results)
                let response = try await networkService.ackInbox(
                    request
                )
                do {
                    try validateInboxAck(request: request, response: response)
                } catch {
                    deferredInboxAckError = error
                }
            }
            _ = try await fetchPendingApprovals()

            // Before the pending check: an upload sets the report's photoURL
            // and marks it pending, and that belongs in THIS push (#141).
            // Never throws — a photo that fails waits for the next sync and
            // must not hold the rest of sync back.
            await reportPhotoUploader?.uploadPending()

            // Any record turning .pending means a snapshot push is due. The
            // snapshot itself is always FULL state — pending is only the trigger.
            let hasPending = try await hasPendingChanges()
            // Exercise has no per-record syncStatus, so inbox-applied changes
            // also set a durable trigger that survives a failed push/restart.
            if settings.isSnapshotDirty || hasPending {
                try await pushSnapshot()
            }
            if let deferredInboxAckError {
                throw deferredInboxAckError
            }
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func hasPendingChanges() async throws -> Bool {
        if try await !workoutRepository.fetchPending().isEmpty { return true }
        if try await !templateRepository.fetchPending().isEmpty { return true }
        if try await !bodyWeightRepository.fetchPending().isEmpty { return true }
        if try await !exerciseReportRepository.fetchPending().isEmpty { return true }
        if try await !bodyMeasurementRepository.fetchPending().isEmpty { return true }
        if try await !medicationRepository.fetchPending().isEmpty { return true }
        if try await !medicationDoseRepository.fetchPending().isEmpty { return true }
        if try await !exerciseAlternativeRepository.fetchPending().isEmpty { return true }
        return false
    }

    private func validateInboxAck(
        request: InboxAckRequest,
        response: InboxAckResponse
    ) throws {
        var issues: [String] = []
        var requested: [String: InboxAckStatus] = [:]
        for result in request.results {
            if requested.updateValue(result.status, forKey: result.id) != nil {
                issues.append("\(result.id): duplicate requested id")
            }
        }
        let received = Dictionary(grouping: response.results, by: \.id)

        for (id, requestedStatus) in requested {
            guard let matches = received[id] else {
                issues.append("\(id): missing result")
                continue
            }
            guard matches.count == 1, let result = matches.first else {
                issues.append("\(id): expected exactly one result")
                continue
            }
            if result.requestedStatus != requestedStatus {
                issues.append(
                    "\(id): requested status \(result.requestedStatus.rawValue) "
                        + "does not match \(requestedStatus.rawValue)"
                )
            }
            switch result.outcome {
            case .notFound:
                issues.append("\(id): operation not found")
            case .conflict:
                issues.append(
                    "\(id): "
                        + (result.conflict
                            ?? "status remained \(result.resultingStatus ?? "unknown")")
                )
            case .updated, .unchanged:
                break
            }
        }
        for id in received.keys where requested[id] == nil {
            issues.append("\(id): extra result")
        }
        if response.counts.notFound > 0,
           !issues.contains(where: {
               $0.localizedCaseInsensitiveContains("not found")
           }) {
            issues.append(
                "Server reported \(response.counts.notFound) not found result(s)"
            )
        }
        if response.counts.invalid > 0,
           !response.results.contains(where: { $0.outcome == .conflict }) {
            issues.append(
                "Server reported \(response.counts.invalid) conflict(s)"
            )
        }
        guard issues.isEmpty else {
            throw SyncError.inboxAckConflict(issues)
        }
    }

    // MARK: - Inbox approvals

    @discardableResult
    func fetchPendingApprovals() async throws -> [InboxOperationDTO] {
        let response = try await networkService.fetchInbox(
            status: .awaitingApproval
        )
        pendingApprovals = response.operations
        return pendingApprovals
    }

    func approve(_ operation: InboxOperationDTO) async throws {
        try await decide([InboxDecision(operation: operation, verdict: .approve)])
    }

    func decline(_ operation: InboxOperationDTO) async throws {
        try await decide([InboxDecision(operation: operation, verdict: .decline)])
    }

    func decide(_ decisions: [InboxDecision]) async throws {
        guard !decisions.isEmpty else { return }
        guard !isSyncing else { throw SyncError.syncInProgress }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            var results: [InboxAckResult] = []
            results.reserveCapacity(decisions.count)
            for decision in decisions {
                switch decision.verdict {
                case .approve:
                    results.append(await inboxApplier.approve(decision.operation))
                case .decline:
                    results.append(inboxApplier.decline(decision.operation))
                }
            }
            let anyApplied = results.contains { $0.status == .applied }
            if anyApplied {
                settings.markSnapshotDirty()
            }
            let request = InboxAckRequest(results: results)
            let response = try await networkService.ackInbox(request)
            var ackValidationError: Error?
            do {
                try validateInboxAck(request: request, response: response)
            } catch {
                ackValidationError = error
            }
            if ackValidationError == nil {
                let decided = Set(decisions.map(\.operation.id))
                pendingApprovals.removeAll { decided.contains($0.id) }
            }

            // Applied batch-mates are pushed before a failure is reported, so
            // one bad operation never strands the others locally.
            if anyApplied {
                try await pushSnapshot()
            }
            if let ackValidationError {
                throw ackValidationError
            }
            let failures = results.filter { $0.status == .failed }
            if !failures.isEmpty {
                throw SyncError.inboxApplyFailed(
                    failures
                        .map { $0.error ?? "Unknown local apply error" }
                        .joined(separator: "\n")
                )
            }
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Push

    /// Serialize the complete local state of the five mirrored types and POST
    /// it as one snapshot. On 200, mark records `.synced` and persist the
    /// server revision. On any failure, everything stays `.pending` and the
    /// next trigger retries — the operation is idempotent by design.
    func pushSnapshot() async throws {
        // Read BEFORE serializing: anything marked dirty from here on did not
        // make it into this payload and must survive the clear below (#104).
        let generation = settings.currentSnapshotGeneration()
        let workouts = try await workoutRepository.fetchAll()
        let templates = try await templateRepository.fetchAll()
        let customExercises = try await exerciseRepository.fetchAll().filter(\.isCustom)
        let bodyWeightEntries = try await bodyWeightRepository.fetchAll()
        let exerciseReports = try await exerciseReportRepository.fetchAll()
        let bodyMeasurements = try await bodyMeasurementRepository.fetchAll()
        let medications = try await medicationRepository.fetchAll()
        let medicationDoses = try await medicationDoseRepository.fetchAll()
        let exerciseAlternatives = try await exerciseAlternativeRepository.fetchAll()
        // Bundled exercises are never mirrored — all ~800 reproduce from the
        // app bundle — but the user data attached to them is irreplaceable
        // and, before #140, was never pushed at all. An exercise with no
        // externalId cannot be keyed and is skipped rather than guessed at.
        let exerciseOverlays = try await exerciseRepository.fetchAll()
            .filter { !$0.isCustom }
            .compactMap { exercise -> ExerciseOverlayDTO? in
                guard let externalId = exercise.externalId, !externalId.isEmpty else { return nil }
                let notes = exercise.notes?.isEmpty == false ? exercise.notes : nil
                let photoURL = exercise.photoURL?.isEmpty == false ? exercise.photoURL : nil
                guard notes != nil || photoURL != nil else { return nil }
                return ExerciseOverlayDTO(id: externalId, notes: notes, photoURL: photoURL)
            }

        // Snapshot lastModified at serialization time: a record edited while
        // the POST is in flight must stay .pending — the server received the
        // old payload, not the edit (issue #74's guarantee, kept in v2).
        let workoutModified = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.lastModified) })
        let templateModified = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0.lastModified) })
        let entryModified = Dictionary(uniqueKeysWithValues: bodyWeightEntries.map { ($0.id, $0.lastModified) })
        let reportModified = Dictionary(uniqueKeysWithValues: exerciseReports.map { ($0.id, $0.lastModified) })
        let measurementModified = Dictionary(uniqueKeysWithValues: bodyMeasurements.map { ($0.id, $0.lastModified) })
        let medicationModified = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0.lastModified) })
        let doseModified = Dictionary(uniqueKeysWithValues: medicationDoses.map { ($0.id, $0.lastModified) })
        let alternativeModified = Dictionary(uniqueKeysWithValues: exerciseAlternatives.map { ($0.id, $0.lastModified) })

        // ALWAYS every collection, even when empty — the server rejects a
        // missing key, and an empty array legitimately means "wipe that type".
        // heightCm is always present too, as null when unset.
        let request = SnapshotPushRequest(
            snapshot: SyncSnapshot(
                workouts: workouts.map { SyncMapper.toDTO($0) },
                templates: templates.map { SyncMapper.toDTO($0) },
                customExercises: customExercises.map { SyncMapper.toDTO($0) },
                bodyWeightEntries: bodyWeightEntries.map { SyncMapper.toDTO($0) },
                exerciseReports: exerciseReports.map { SyncMapper.toDTO($0) },
                exerciseOverlays: exerciseOverlays,
                bodyMeasurements: bodyMeasurements.map { SyncMapper.toDTO($0) },
                medications: medications.map { SyncMapper.toDTO($0) },
                medicationDoses: medicationDoses.map { SyncMapper.toDTO($0) },
                exerciseAlternatives: exerciseAlternatives.map { SyncMapper.toDTO($0) },
                heightCm: settings.heightCm
            )
        )

        let response = try await push(request)

        for workout in workouts where workout.lastModified == workoutModified[workout.id] {
            workout.syncStatus = .synced
        }
        for template in templates where template.lastModified == templateModified[template.id] {
            template.syncStatus = .synced
        }
        for entry in bodyWeightEntries where entry.lastModified == entryModified[entry.id] {
            entry.syncStatus = .synced
        }
        for report in exerciseReports where report.lastModified == reportModified[report.id] {
            report.syncStatus = .synced
        }
        // Marked synced even when the push degraded to v4 and the server did
        // not store them: `syncStatus` is only the local "is a push due" bit,
        // and every push is full state, so the first push to an upgraded
        // server carries them regardless.
        for measurement in bodyMeasurements where measurement.lastModified == measurementModified[measurement.id] {
            measurement.syncStatus = .synced
        }
        for medication in medications where medication.lastModified == medicationModified[medication.id] {
            medication.syncStatus = .synced
        }
        for dose in medicationDoses where dose.lastModified == doseModified[dose.id] {
            dose.syncStatus = .synced
        }
        for alternative in exerciseAlternatives where alternative.lastModified == alternativeModified[alternative.id] {
            alternative.syncStatus = .synced
        }

        recordSuccess(revision: response.revision, serverTime: response.serverTime)
        settings.markSnapshotClean(upTo: generation)
    }

    /// Sends the push, degrading one wire version at a time while the server
    /// rejects them.
    ///
    /// The Functions app and the phone deploy independently, and there is no
    /// ordering guarantee between them. Without this, installing a build whose
    /// wire version the server has not learned yet breaks sync *entirely* —
    /// not just the new collection — until someone remembers to deploy. A 400
    /// is the server saying "I do not know this schemaVersion"; anything else
    /// is a real failure and is rethrown untouched, as is a 400 at the oldest
    /// version. The snapshot is sent unchanged at every version: a server only
    /// reconciles the collections its version names and ignores other keys.
    private func push(_ request: SnapshotPushRequest) async throws -> SnapshotPushResponse {
        var attempt = request
        var fallbacks = SnapshotPushRequest.fallbackSchemaVersions
            .filter { $0 < request.schemaVersion }
        while true {
            do {
                return try await networkService.pushSnapshot(attempt)
            } catch SyncError.serverError(400) where !fallbacks.isEmpty {
                attempt = SnapshotPushRequest(
                    schemaVersion: fallbacks.removeFirst(),
                    snapshot: request.snapshot
                )
            }
        }
    }

    // MARK: - Restore

    /// Disaster recovery: fetch the cloud mirror and REPLACE local data for the
    /// five mirrored types. Never touches chat history, insights, preferences,
    /// or the bundled exercise library. Destructive — callers must confirm with
    /// the user first (Settings does).
    func restoreFromSnapshot() async throws -> RestoreSummary {
        guard !isSyncing else { throw SyncError.syncInProgress }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let response = try await networkService.fetchSnapshot()

            // A fresh mirror (never pushed to) reads as revision 0 with
            // empty arrays. Wiping local data with that would be data loss
            // dressed up as a restore — refuse.
            guard response.revision > 0 else { throw SyncError.emptyMirror }

            let snapshot = response.snapshot
            var summary = RestoreSummary()
            summary.revision = response.revision
            // The v5 repositories flag deletions, and restoring the height is
            // a settings change; both mark the snapshot dirty. Neither leaves
            // a push due once local state equals the mirror (see the end).
            let wasDirtyBeforeRestore = settings.isSnapshotDirty

            // Alternatives hang off template exercises by plain UUID, and the
            // template wipe below cleans up orphans — so a mirror that cannot
            // give them back (pre-v5) would silently cost the user every one.
            // Keep them aside and re-attach any whose slot comes back.
            let preservedAlternatives: [ExerciseAlternativeDTO] = snapshot.carriesV5Collections
                ? []
                : try await exerciseAlternativeRepository.fetchAll().map { SyncMapper.toDTO($0) }

            // 1. Wipe the mirrored types. The v5 ones only when the mirror
            //    actually carries them: absent means unknown, not empty.
            if snapshot.carriesV5Collections {
                for measurement in try await bodyMeasurementRepository.fetchAll() {
                    try await bodyMeasurementRepository.delete(measurement)
                }
                for dose in try await medicationDoseRepository.fetchAll() {
                    try await medicationDoseRepository.delete(dose)
                }
                for medication in try await medicationRepository.fetchAll() {
                    try await medicationRepository.delete(medication)
                }
                for alternative in try await exerciseAlternativeRepository.fetchAll() {
                    try await exerciseAlternativeRepository.delete(alternative)
                }
            }
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
            for report in try await exerciseReportRepository.fetchAll() {
                try await exerciseReportRepository.delete(report)
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

            for dto in snapshot.exerciseReports {
                try await exerciseReportRepository.save(
                    SyncMapper.createExerciseReport(from: dto)
                )
                summary.exerciseReports += 1
            }

            // 5b. schemaVersion 5. Alternatives go AFTER templates: a template
            //     save cleans up alternatives whose slot is not in a template.
            if snapshot.carriesV5Collections {
                for dto in snapshot.bodyMeasurements {
                    try await bodyMeasurementRepository.save(SyncMapper.createBodyMeasurement(from: dto))
                    summary.bodyMeasurements += 1
                }
                var restoredMedications: [UUID: Medication] = [:]
                for dto in snapshot.medications {
                    let medication = SyncMapper.createMedication(from: dto)
                    try await medicationRepository.save(medication)
                    restoredMedications[medication.id] = medication
                    summary.medications += 1
                }
                for dto in snapshot.medicationDoses {
                    // A dose whose medication is missing from the mirror is
                    // still restored, unattached, rather than dropped.
                    let medication = dto.medicationId.flatMap { restoredMedications[$0] }
                    try await medicationDoseRepository.save(
                        SyncMapper.createMedicationDose(from: dto, medication: medication)
                    )
                    summary.medicationDoses += 1
                }
                for dto in snapshot.exerciseAlternatives {
                    try await exerciseAlternativeRepository.save(SyncMapper.createExerciseAlternative(from: dto))
                    summary.exerciseAlternatives += 1
                }
                // Never cleared by a restore: a mirror without a height is
                // not evidence that the user has none.
                if let heightCm = snapshot.heightCm {
                    settings.heightCm = heightCm
                }
            } else if !preservedAlternatives.isEmpty {
                let restoredSlots = Set(snapshot.templates.flatMap { $0.exercises.map(\.id) })
                for dto in preservedAlternatives where restoredSlots.contains(dto.templateExerciseId) {
                    try await exerciseAlternativeRepository.save(SyncMapper.createExerciseAlternative(from: dto))
                }
            }

            // 6. Overlays LAST, and by externalId — the bundled library was
            //    re-imported with fresh UUIDs, so this is the only key that
            //    still means anything (#140). An overlay for an exercise this
            //    build does not ship is dropped, not an error: the library can
            //    change between the backup and the restore.
            if !snapshot.exerciseOverlays.isEmpty {
                let installed = try await exerciseRepository.fetchAll()
                let byExternalId = Dictionary(
                    installed.compactMap { exercise -> (String, Exercise)? in
                        guard let externalId = exercise.externalId else { return nil }
                        return (externalId, exercise)
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                for dto in snapshot.exerciseOverlays {
                    guard let exercise = byExternalId[dto.id] else { continue }
                    if let notes = dto.notes { exercise.notes = notes }
                    if let photoURL = dto.photoURL { exercise.photoURL = photoURL }
                    try await exerciseRepository.save(exercise)
                    summary.exerciseOverlays += 1
                }
            }

            // Local now equals the mirror, so the dirt this restore made is
            // not a push due. Two exceptions keep it dirty: the phone was
            // already dirty before (that change may not be mirrored), or the
            // phone kept a height the mirror lacks.
            let keptHeightMirrorLacks = snapshot.carriesV5Collections
                && snapshot.heightCm == nil && settings.heightCm != nil
            if !wasDirtyBeforeRestore && !keptHeightMirrorLacks {
                settings.markSnapshotClean(upTo: settings.currentSnapshotGeneration())
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
