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

/// A body circumference (#165). `site` stays a raw string on the wire, like
/// report categories, so a site added by a newer build round-trips.
struct BodyMeasurementDTO: Codable, Sendable, Equatable {
    let id: UUID
    let site: String
    let valueCm: Double
    let recordedAt: Date
    let note: String?
    let lastModified: Date
}

/// A user-defined medication (#164). Enum fields stay raw strings.
/// Concentration is EITHER `concentrationMgPerMl` OR `vialAmountMg` ÷
/// `diluentMl`; the direct value wins when both are present.
struct MedicationDTO: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    /// "mass" | "tablet" | "liquid" | "units"
    let doseForm: String
    /// "mg" | "mcg" | "g", for doseForm "mass".
    let massUnit: String?
    let tabletStrengthMg: Double?
    let concentrationMgPerMl: Double?
    let vialAmountMg: Double?
    let diluentMl: Double?
    let allowsSyringeUnits: Bool
    let isArchived: Bool
    let createdAt: Date
    let lastModified: Date
}

/// One logged dose (#164). `computedMg`, `concentrationMgPerMlAtLog` and
/// `tabletStrengthMgAtLog` are what the phone computed and snapshotted at log
/// time — readers must use them as stored and never recompute from the
/// medication's current values.
struct MedicationDoseDTO: Codable, Sendable, Equatable {
    let id: UUID
    /// The owning medication. Optional only for tolerance; the phone cascades
    /// dose deletion with its medication, so it is always present in practice.
    let medicationId: UUID?
    let takenAt: Date
    let amount: Double
    /// "mg" | "mcg" | "g" | "tablet" | "mL" | "syringeUnits" | "IU"
    let unit: String
    let computedMg: Double?
    let concentrationMgPerMlAtLog: Double?
    /// The tablet strength snapshotted at log time. Absent from payloads
    /// written before it existed, which decode as nil.
    let tabletStrengthMgAtLog: Double?
    let note: String?
    let lastModified: Date

    init(
        id: UUID,
        medicationId: UUID?,
        takenAt: Date,
        amount: Double,
        unit: String,
        computedMg: Double?,
        concentrationMgPerMlAtLog: Double?,
        tabletStrengthMgAtLog: Double? = nil,
        note: String?,
        lastModified: Date
    ) {
        self.id = id
        self.medicationId = medicationId
        self.takenAt = takenAt
        self.amount = amount
        self.unit = unit
        self.computedMg = computedMg
        self.concentrationMgPerMlAtLog = concentrationMgPerMlAtLog
        self.tabletStrengthMgAtLog = tabletStrengthMgAtLog
        self.note = note
        self.lastModified = lastModified
    }
}

/// A substitute listed on a template exercise. `templateExerciseId` matches a
/// `TemplateExerciseDTO.id` inside some `TemplateDTO.exercises`; `externalId`
/// is the catalog (or `custom:`) id of the alternative exercise.
struct ExerciseAlternativeDTO: Codable, Sendable, Equatable {
    let id: UUID
    let templateExerciseId: UUID
    let externalId: String
    let order: Int
    let note: String?
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
    /// schemaVersion 5 (#165).
    let bodyMeasurements: [BodyMeasurementDTO]
    /// schemaVersion 5 (#164).
    let medications: [MedicationDTO]
    /// schemaVersion 5 (#164).
    let medicationDoses: [MedicationDoseDTO]
    /// schemaVersion 5: template-exercise alternatives.
    let exerciseAlternatives: [ExerciseAlternativeDTO]
    /// schemaVersion 5 (#165): the profile height, a scalar rather than a
    /// collection. Always ENCODED, as null when unset — "no height" is a value
    /// the mirror must hold, not a key it may skip.
    let heightCm: Double?
    /// Whether this snapshot actually carried the v5 keys. Not on the wire.
    ///
    /// A mirror last written by a v4 server (or a v4 client) has no v5 keys,
    /// and they decode as empty. Restore must read that as "unknown", not as
    /// "the user has no medications" — otherwise restoring from a server that
    /// was never upgraded would wipe the phone's v5 data. Same rule the server
    /// applies to pushes: absent from the contract means untouched.
    let carriesV5Collections: Bool

    init(
        workouts: [WorkoutDTO],
        templates: [TemplateDTO],
        customExercises: [ExerciseDTO],
        bodyWeightEntries: [BodyWeightEntryDTO],
        exerciseReports: [ExerciseReportDTO] = [],
        exerciseOverlays: [ExerciseOverlayDTO] = [],
        bodyMeasurements: [BodyMeasurementDTO] = [],
        medications: [MedicationDTO] = [],
        medicationDoses: [MedicationDoseDTO] = [],
        exerciseAlternatives: [ExerciseAlternativeDTO] = [],
        heightCm: Double? = nil
    ) {
        self.workouts = workouts
        self.templates = templates
        self.customExercises = customExercises
        self.bodyWeightEntries = bodyWeightEntries
        self.exerciseReports = exerciseReports
        self.exerciseOverlays = exerciseOverlays
        self.bodyMeasurements = bodyMeasurements
        self.medications = medications
        self.medicationDoses = medicationDoses
        self.exerciseAlternatives = exerciseAlternatives
        self.heightCm = heightCm
        self.carriesV5Collections = true
    }

    private enum CodingKeys: String, CodingKey {
        case workouts, templates, customExercises, bodyWeightEntries
        case exerciseReports, exerciseOverlays
        case bodyMeasurements, medications, medicationDoses, exerciseAlternatives
        case heightCm
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
        // A v5 mirror always writes all four arrays together; requiring every
        // one keeps a partial payload from being mistaken for a full one.
        carriesV5Collections = container.contains(.bodyMeasurements)
            && container.contains(.medications)
            && container.contains(.medicationDoses)
            && container.contains(.exerciseAlternatives)
        bodyMeasurements = try container.decodeIfPresent(
            [BodyMeasurementDTO].self, forKey: .bodyMeasurements
        ) ?? []
        medications = try container.decodeIfPresent(
            [MedicationDTO].self, forKey: .medications
        ) ?? []
        medicationDoses = try container.decodeIfPresent(
            [MedicationDoseDTO].self, forKey: .medicationDoses
        ) ?? []
        exerciseAlternatives = try container.decodeIfPresent(
            [ExerciseAlternativeDTO].self, forKey: .exerciseAlternatives
        ) ?? []
        heightCm = try container.decodeIfPresent(Double.self, forKey: .heightCm)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workouts, forKey: .workouts)
        try container.encode(templates, forKey: .templates)
        try container.encode(customExercises, forKey: .customExercises)
        try container.encode(bodyWeightEntries, forKey: .bodyWeightEntries)
        try container.encode(exerciseReports, forKey: .exerciseReports)
        try container.encode(exerciseOverlays, forKey: .exerciseOverlays)
        try container.encode(bodyMeasurements, forKey: .bodyMeasurements)
        try container.encode(medications, forKey: .medications)
        try container.encode(medicationDoses, forKey: .medicationDoses)
        try container.encode(exerciseAlternatives, forKey: .exerciseAlternatives)
        // Explicit null, not an omitted key — see `heightCm`.
        if let heightCm {
            try container.encode(heightCm, forKey: .heightCm)
        } else {
            try container.encodeNil(forKey: .heightCm)
        }
    }
}

struct SnapshotPushRequest: Codable, Sendable {
    /// Wire contract the client speaks. 4 adds `exerciseOverlays` (#140);
    /// 5 adds body measurements, medications, doses, alternatives and height.
    static let currentSchemaVersion = 5
    /// Older contracts to degrade to, newest first, when the server rejects a
    /// version with 400 because it has not been deployed yet. The Functions
    /// app deploys independently of the phone, and the phone can ship first —
    /// see SyncManager.push. Every step down is safe: a server only reconciles
    /// the collections its own version names and ignores the rest. The last
    /// entry is the oldest contract this client will speak.
    static let fallbackSchemaVersions = [4, 3]

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
