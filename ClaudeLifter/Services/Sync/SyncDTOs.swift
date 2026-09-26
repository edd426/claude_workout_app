import Foundation

// Wire format DTOs for the v2 one-way snapshot sync API (issue #78).
//
// SwiftData on the phone is authoritative. Sync is a full-state snapshot
// mirror phone → Azure; the mirror exists only for MCP reads and disaster
// restore. Dates are ISO 8601 with fractional seconds (see NetworkService's
// wire codecs); ids are UUID strings.

struct WorkoutSetDTO: Codable, Sendable {
    let id: UUID
    let order: Int
    let weight: Double?
    let weightUnit: String  // "kg" or "lbs"
    let reps: Int?
    let isCompleted: Bool
    let completedAt: Date?
    let notes: String?
}

struct WorkoutExerciseDTO: Codable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String?
    let order: Int
    let notes: String?
    let restSeconds: Int
    let sets: [WorkoutSetDTO]

    init(
        id: UUID,
        exerciseId: UUID,
        exerciseName: String? = nil,
        order: Int,
        notes: String?,
        restSeconds: Int,
        sets: [WorkoutSetDTO]
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.notes = notes
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

struct WorkoutDTO: Codable, Sendable {
    let id: UUID
    let templateId: UUID?
    let name: String
    let startedAt: Date
    let completedAt: Date?
    let notes: String?
    let lastModified: Date
    let exercises: [WorkoutExerciseDTO]
}

struct TemplateExerciseDTO: Codable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String?
    let order: Int
    let defaultSets: Int
    let defaultReps: Int
    let defaultWeight: Double?
    let defaultRestSeconds: Int
    let notes: String?

    init(
        id: UUID,
        exerciseId: UUID,
        exerciseName: String? = nil,
        order: Int,
        defaultSets: Int,
        defaultReps: Int,
        defaultWeight: Double?,
        defaultRestSeconds: Int,
        notes: String?
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.defaultWeight = defaultWeight
        self.defaultRestSeconds = defaultRestSeconds
        self.notes = notes
    }
}

struct TemplateDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let lastPerformedAt: Date?
    let timesPerformed: Int
    let lastModified: Date
    let exercises: [TemplateExerciseDTO]
}

/// Full-fidelity wire representation of an `Exercise`. Only CUSTOM exercises
/// travel over the wire (bundled ones re-import from the app bundle). Also the
/// on-disk shape of BackupService's `customExercises` array (field-compatible
/// with the former ExerciseBackupDTO, so old backup files still decode).
struct ExerciseDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let instructions: [String]
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let isCustom: Bool
    let externalId: String?
    let notes: String?
    let imageURL: String?
    let photoURL: String?
    let tags: [ExerciseTagDTO]
}

/// Tag content only — a fresh ExerciseTag id is minted on restore to avoid
/// colliding with existing tag ids in the destination store.
struct ExerciseTagDTO: Codable, Sendable {
    let category: String
    let value: String
}

struct BodyWeightEntryDTO: Codable, Sendable {
    let id: UUID
    let weightKg: Double
    let recordedAt: Date
    let source: String  // "manual" | "healthkit"
    let healthKitSampleUUID: UUID?
    let lastModified: Date
}

/// A user-filed complaint (issue #135). Mirrored so the MCP server can read
/// the backlog; `category`/`status` stay raw strings on the wire so an
/// unrecognised value from a newer app build round-trips instead of failing
/// the whole snapshot.
struct ExerciseReportDTO: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let category: String
    let detail: String
    let exerciseExternalId: String?
    let exerciseName: String?
    let suggestedReplacement: String?
    let workoutId: UUID?
    let workoutExerciseId: UUID?
    let templateId: UUID?
    let contextSummary: String?
    let status: String
    let resolution: String?
    let appVersion: String?
    let iosVersion: String?
    let photoURL: String?
    let lastModified: Date
}

/// Still on the wire for local backup files only (BackupService). Preferences
/// are NOT part of cloud sync — that path caused the pull ping-pong (#78).
struct PreferenceDTO: Codable, Sendable {
    let id: UUID
    let key: String
    let value: String
    let source: String?
    let lastModified: Date
}

/// User data layered onto a *bundled* exercise — the machine note and the
/// photo. Bundled exercises themselves are never synced (all ~800 reproduce
/// from the app bundle), so before #140 this data existed only on the device
/// that typed it.
///
/// Keyed by `externalId`, the stable free-exercise-db identifier, and NOT by
/// `Exercise.id`: a reinstall re-imports the library with fresh UUIDs, so a
/// UUID key would orphan every overlay exactly when it was needed most.
///
/// `id` is the Cosmos document key and carries the same value. Both keys are
/// written, and either is accepted on decode, because backup files produced
/// by 1.4.0 wrote only `externalId`.
struct ExerciseOverlayDTO: Codable, Sendable, Equatable {
    let id: String
    let notes: String?
    let photoURL: String?

    var externalId: String? { id }

    init(id: String, notes: String?, photoURL: String?) {
        self.id = id
        self.notes = notes
        self.photoURL = photoURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, externalId, notes, photoURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .id) {
            self.id = id
        } else {
            self.id = try c.decode(String.self, forKey: .externalId)
        }
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        photoURL = try c.decodeIfPresent(String.self, forKey: .photoURL)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(id, forKey: .externalId)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(photoURL, forKey: .photoURL)
    }
}

// MARK: - Snapshot request/response (POST/GET /api/sync/snapshot)

/// The complete mirrored state. ALWAYS carries all five collections — the
/// server rejects a missing key (400), and an empty array means "wipe that
/// type on the server". That is how deletions propagate: no tombstones, the
/// server deletes any doc absent from the snapshot.
///
/// `exerciseReports` arrived with schemaVersion 3 (issue #135). It decodes as
/// empty when absent so a v2 payload — an old backup file, or the GET of a
/// mirror last written by a v2 client — still restores.
struct SyncSnapshot: Codable, Sendable {
    let workouts: [WorkoutDTO]
    let templates: [TemplateDTO]
    let customExercises: [ExerciseDTO]
    let bodyWeightEntries: [BodyWeightEntryDTO]
    let exerciseReports: [ExerciseReportDTO]
    /// Arrived with schemaVersion 4 (issue #140). Decodes as empty when
    /// absent, for the same reason `exerciseReports` does.
    let exerciseOverlays: [ExerciseOverlayDTO]

    init(
        workouts: [WorkoutDTO],
        templates: [TemplateDTO],
        customExercises: [ExerciseDTO],
        bodyWeightEntries: [BodyWeightEntryDTO],
        exerciseReports: [ExerciseReportDTO] = [],
        exerciseOverlays: [ExerciseOverlayDTO] = []
    ) {
        self.workouts = workouts
        self.templates = templates
        self.customExercises = customExercises
        self.bodyWeightEntries = bodyWeightEntries
        self.exerciseReports = exerciseReports
        self.exerciseOverlays = exerciseOverlays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workouts = try container.decode([WorkoutDTO].self, forKey: .workouts)
        templates = try container.decode([TemplateDTO].self, forKey: .templates)
        customExercises = try container.decode([ExerciseDTO].self, forKey: .customExercises)
        bodyWeightEntries = try container.decode(
            [BodyWeightEntryDTO].self, forKey: .bodyWeightEntries
        )
        exerciseReports = try container.decodeIfPresent(
            [ExerciseReportDTO].self, forKey: .exerciseReports
        ) ?? []
        exerciseOverlays = try container.decodeIfPresent(
            [ExerciseOverlayDTO].self, forKey: .exerciseOverlays
        ) ?? []
    }
}

struct SnapshotPushRequest: Codable, Sendable {
    /// Wire contract the client speaks. 4 adds `exerciseOverlays` (#140).
    static let currentSchemaVersion = 4
    /// What to fall back to when the server has not been updated yet. The
    /// Functions app deploys independently of the phone, and this time the
    /// phone can ship first — see SyncManager.pushSnapshot.
    static let fallbackSchemaVersion = 3

    let schemaVersion: Int
    let snapshot: SyncSnapshot

    init(schemaVersion: Int = SnapshotPushRequest.currentSchemaVersion, snapshot: SyncSnapshot) {
        self.schemaVersion = schemaVersion
        self.snapshot = snapshot
    }
}

struct SnapshotCollectionCounts: Codable, Sendable {
    let upserted: Int
    let deleted: Int
}

struct SnapshotPushResponse: Codable, Sendable {
    /// Server-assigned, monotonically increasing. 0 means the mirror has
    /// never received a push.
    let revision: Int
    let serverTime: Date
    let counts: [String: SnapshotCollectionCounts]
}

struct SnapshotFetchResponse: Codable, Sendable {
    let revision: Int
    let serverTime: Date
    let snapshot: SyncSnapshot
}
