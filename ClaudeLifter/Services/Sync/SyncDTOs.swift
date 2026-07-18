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

/// Still on the wire for local backup files only (BackupService). Preferences
/// are NOT part of cloud sync — that path caused the pull ping-pong (#78).
struct PreferenceDTO: Codable, Sendable {
    let id: UUID
    let key: String
    let value: String
    let source: String?
    let lastModified: Date
}

// MARK: - Snapshot request/response (POST/GET /api/sync/snapshot)

/// The complete mirrored state. ALWAYS carries all four collections — the
/// server rejects a missing key (400), and an empty array means "wipe that
/// type on the server". That is how deletions propagate: no tombstones, the
/// server deletes any doc absent from the snapshot.
struct SyncSnapshot: Codable, Sendable {
    let workouts: [WorkoutDTO]
    let templates: [TemplateDTO]
    let customExercises: [ExerciseDTO]
    let bodyWeightEntries: [BodyWeightEntryDTO]
}

struct SnapshotPushRequest: Codable, Sendable {
    let schemaVersion: Int
    let snapshot: SyncSnapshot

    init(schemaVersion: Int = 2, snapshot: SyncSnapshot) {
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
