import Foundation
import SwiftData

// MARK: - Backup wire format

/// User data attached to a **bundled** exercise (#140).
///
/// The exercise itself re-imports from the app bundle, so carrying all 800 of
/// them would be waste — but the notes and photo the user attached to one are
/// not in the bundle and are lost forever without this.
///
/// Keyed by `externalId`, never by `id`: a reinstall re-imports the catalog
/// with brand-new random UUIDs, so a UUID-keyed overlay would attach to
/// nothing. Same identity rule as the MCP write path.
// `ExerciseOverlayDTO` now lives in Services/Sync/SyncDTOs.swift — the backup
// file and the snapshot wire carry the same shape, and #140's sync half needed
// a non-optional `id` for the Cosmos document key. Files written by 1.4.0 with
// only `externalId` still decode.

/// A device-local JSON backup: everything the user would lose if the store were
/// wiped and cloud sync had never run. Bundled (non-custom) exercises are not
/// carried in full — they re-import from the app bundle — but the user data
/// attached to them travels as `exerciseOverlays` (#140).
struct BackupDocument: Codable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let workouts: [WorkoutDTO]
    let templates: [TemplateDTO]
    /// Same full-fidelity `ExerciseDTO` as the v2 snapshot wire format —
    /// field-compatible with the former ExerciseBackupDTO, so backup files
    /// written before issue #78 still decode.
    let customExercises: [ExerciseDTO]
    let preferences: [PreferenceDTO]
    /// Present from formatVersion 2. Decodes as empty for older files, which
    /// import unchanged — the same tolerance the snapshot wire format uses
    /// for `exerciseReports`.
    let exerciseOverlays: [ExerciseOverlayDTO]
    /// formatVersion 3 (#165, #164, template alternatives). Same DTOs as the
    /// snapshot wire; each decodes as empty from an older file.
    let bodyMeasurements: [BodyMeasurementDTO]
    let medications: [MedicationDTO]
    let medicationDoses: [MedicationDoseDTO]
    let exerciseAlternatives: [ExerciseAlternativeDTO]
    /// formatVersion 3. Nil when unset, or from an older file.
    let heightCm: Double?

    init(
        formatVersion: Int,
        exportedAt: Date,
        workouts: [WorkoutDTO],
        templates: [TemplateDTO],
        customExercises: [ExerciseDTO],
        preferences: [PreferenceDTO],
        exerciseOverlays: [ExerciseOverlayDTO] = [],
        bodyMeasurements: [BodyMeasurementDTO] = [],
        medications: [MedicationDTO] = [],
        medicationDoses: [MedicationDoseDTO] = [],
        exerciseAlternatives: [ExerciseAlternativeDTO] = [],
        heightCm: Double? = nil
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.workouts = workouts
        self.templates = templates
        self.customExercises = customExercises
        self.preferences = preferences
        self.exerciseOverlays = exerciseOverlays
        self.bodyMeasurements = bodyMeasurements
        self.medications = medications
        self.medicationDoses = medicationDoses
        self.exerciseAlternatives = exerciseAlternatives
        self.heightCm = heightCm
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        workouts = try c.decode([WorkoutDTO].self, forKey: .workouts)
        templates = try c.decode([TemplateDTO].self, forKey: .templates)
        customExercises = try c.decode([ExerciseDTO].self, forKey: .customExercises)
        preferences = try c.decode([PreferenceDTO].self, forKey: .preferences)
        exerciseOverlays = try c.decodeIfPresent(
            [ExerciseOverlayDTO].self,
            forKey: .exerciseOverlays
        ) ?? []
        bodyMeasurements = try c.decodeIfPresent([BodyMeasurementDTO].self, forKey: .bodyMeasurements) ?? []
        medications = try c.decodeIfPresent([MedicationDTO].self, forKey: .medications) ?? []
        medicationDoses = try c.decodeIfPresent([MedicationDoseDTO].self, forKey: .medicationDoses) ?? []
        exerciseAlternatives = try c.decodeIfPresent(
            [ExerciseAlternativeDTO].self,
            forKey: .exerciseAlternatives
        ) ?? []
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm)
    }
}

// MARK: - Import errors

enum BackupError: Error, LocalizedError {
    /// The backup references exercises that exist neither locally nor in the
    /// backup itself. Importing anyway would silently produce workouts and
    /// templates with missing exercises (the SyncMapper factories drop
    /// unresolvable references), and a re-import could not repair them because
    /// the parents would already exist by id.
    case unresolvedExercises([String])

    var errorDescription: String? {
        switch self {
        case .unresolvedExercises(let names):
            return "Backup not imported: \(names.count) exercise reference(s) could not be resolved (\(names.prefix(3).joined(separator: ", "))\(names.count > 3 ? ", …" : "")). Nothing was changed."
        }
    }
}

// MARK: - Import summary

/// Per-collection outcome of an import: how many records were newly written and
/// how many were skipped because their id already existed locally.
struct BackupImportSummary: Sendable, Equatable {
    struct CollectionResult: Sendable, Equatable {
        var imported: Int = 0
        var skipped: Int = 0
    }

    var customExercises = CollectionResult()
    var templates = CollectionResult()
    var workouts = CollectionResult()
    var preferences = CollectionResult()
    /// Bundled-exercise user data (#140). `skipped` means the overlay had no
    /// matching exercise locally — it is never used to invent one.
    var exerciseOverlays = CollectionResult()
    var bodyMeasurements = CollectionResult()
    var medications = CollectionResult()
    /// `skipped` also counts a dose whose medication is in neither the backup
    /// nor this phone — imported, it would be an orphan.
    var medicationDoses = CollectionResult()
    /// `skipped` also counts an alternative whose template exercise is in no
    /// template here.
    var exerciseAlternatives = CollectionResult()
    /// True when the backup's height was written. Never overwrites a height
    /// this phone already has.
    var heightImported = false
}

// MARK: - Service

@MainActor
protocol BackupServiceProtocol {
    /// Encode all workouts, templates, custom exercises, preferences, body
    /// measurements, medications and doses, template-exercise alternatives,
    /// and height into a JSON file in the app's Documents directory and
    /// return its URL. (Body-weight entries and exercise reports are not in
    /// the backup file; they are mirrored by snapshot sync only.)
    func exportBackup() async throws -> URL
    /// Decode a backup file and merge it into the local store by id, skipping any
    /// record whose id already exists (conservative — never overwrites).
    func importBackup(from url: URL) async throws -> BackupImportSummary
}

@MainActor
final class BackupService: BackupServiceProtocol {
    private let modelContext: ModelContext
    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let exerciseRepository: any ExerciseRepository
    private let preferenceRepository: any TrainingPreferenceRepository
    private let bodyMeasurementRepository: any BodyMeasurementRepository
    private let medicationRepository: any MedicationRepository
    private let medicationDoseRepository: any MedicationDoseRepository
    private let exerciseAlternativeRepository: any ExerciseAlternativeRepository
    /// Height lives here, not in SwiftData (#165).
    private let settings: SettingsManager
    private let documentsDirectory: URL

    init(
        modelContext: ModelContext,
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository,
        preferenceRepository: any TrainingPreferenceRepository,
        bodyMeasurementRepository: any BodyMeasurementRepository,
        medicationRepository: any MedicationRepository,
        medicationDoseRepository: any MedicationDoseRepository,
        exerciseAlternativeRepository: any ExerciseAlternativeRepository,
        settings: SettingsManager,
        documentsDirectory: URL = URL.documentsDirectory
    ) {
        self.modelContext = modelContext
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
        self.preferenceRepository = preferenceRepository
        self.bodyMeasurementRepository = bodyMeasurementRepository
        self.medicationRepository = medicationRepository
        self.medicationDoseRepository = medicationDoseRepository
        self.exerciseAlternativeRepository = exerciseAlternativeRepository
        self.settings = settings
        self.documentsDirectory = documentsDirectory
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Human-inspectable and deterministic. Default date strategy keeps full
        // precision so `lastModified` timestamps round-trip exactly (important
        // for last-write-wins once these records reach the sync push cycle).
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Export

    func exportBackup() async throws -> URL {
        let workouts = try await workoutRepository.fetchAll().map { SyncMapper.toDTO($0) }
        let templates = try await templateRepository.fetchAll().map { SyncMapper.toDTO($0) }
        let customExercises = try await exerciseRepository.fetchAll()
            .filter { $0.isCustom }
            .map { SyncMapper.toDTO($0) }
        let preferences = try await preferenceRepository.fetchAll().map { SyncMapper.toDTO($0) }
        // Only bundled exercises that actually carry user data (#140) — the
        // other ~800 are reproduced from the app bundle on import.
        let overlays = try await exerciseRepository.fetchAll()
            .filter { !$0.isCustom && $0.externalId != nil }
            .filter { $0.notes?.isEmpty == false || $0.photoURL?.isEmpty == false }
            .map {
                ExerciseOverlayDTO(
                    id: $0.externalId ?? "",
                    notes: $0.notes,
                    photoURL: $0.photoURL
                )
            }

        let document = BackupDocument(
            formatVersion: 3,
            exportedAt: .now,
            workouts: workouts,
            templates: templates,
            customExercises: customExercises,
            preferences: preferences,
            exerciseOverlays: overlays,
            bodyMeasurements: try await bodyMeasurementRepository.fetchAll().map { SyncMapper.toDTO($0) },
            medications: try await medicationRepository.fetchAll().map { SyncMapper.toDTO($0) },
            medicationDoses: try await medicationDoseRepository.fetchAll().map { SyncMapper.toDTO($0) },
            exerciseAlternatives: try await exerciseAlternativeRepository.fetchAll().map { SyncMapper.toDTO($0) },
            heightCm: settings.heightCm
        )

        let data = try encoder.encode(document)
        let fileName = "claudelifter-backup-\(Self.fileDateFormatter.string(from: .now)).json"
        let url = documentsDirectory.appending(path: fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    func importBackup(from url: URL) async throws -> BackupImportSummary {
        // fileImporter hands back a security-scoped URL that must be explicitly
        // accessed before reading. Harmless for plain file URLs (returns false).
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let document = try decoder.decode(BackupDocument.self, from: data)

        // Preflight BEFORE any mutation: every exercise referenced by a
        // template/workout that will actually be imported must be resolvable —
        // locally, from the backup's own custom exercises, or by name.
        try await preflightExerciseReferences(in: document)

        var summary = BackupImportSummary()

        // 1. Custom exercises FIRST so templates/workouts can resolve references.
        for dto in document.customExercises {
            if try await exerciseRepository.fetch(id: dto.id) != nil {
                summary.customExercises.skipped += 1
                continue
            }
            insertExercise(from: dto)
            try modelContext.save()
            summary.customExercises.imported += 1
        }

        // 2. Templates (resolve exercise references via SyncMapper).
        for dto in document.templates {
            if try await templateRepository.fetch(id: dto.id) != nil {
                summary.templates.skipped += 1
                continue
            }
            let template = try await SyncMapper.createTemplate(
                from: dto,
                exerciseRepository: exerciseRepository
            )
            // Factory marks records .synced; a restore is a *local* change that
            // must push to Azure, so force it back to .pending.
            template.syncStatus = .pending
            try await templateRepository.save(template)
            summary.templates.imported += 1
        }

        // 3. Workouts (resolve exercise references via SyncMapper).
        for dto in document.workouts {
            if try await workoutRepository.fetch(id: dto.id) != nil {
                summary.workouts.skipped += 1
                continue
            }
            let workout = try await SyncMapper.createWorkout(
                from: dto,
                exerciseRepository: exerciseRepository
            )
            workout.syncStatus = .pending
            try await workoutRepository.save(workout)
            summary.workouts.imported += 1
        }

        // 4. Preferences. Identity is by KEY operationally (the app upserts by
        // key), so merge by key too — matching only on UUID could insert a
        // second record with the same key and make lookups order-dependent.
        let existingKeys = Set(try await preferenceRepository.fetchAll().map(\.key))
        for dto in document.preferences {
            if try await preferenceRepository.fetch(id: dto.id) != nil
                || existingKeys.contains(dto.key) {
                summary.preferences.skipped += 1
                continue
            }
            let preference = SyncMapper.createPreference(from: dto)
            preference.syncStatus = .pending
            modelContext.insert(preference)
            try modelContext.save()
            summary.preferences.imported += 1
        }

        // 5. Bundled-exercise user data (#140). Applied LAST, and unlike every
        // other collection this one overwrites rather than skips: restoring a
        // backup means "make this device look like the backup", and the
        // overlay is the only copy of a machine setting that exists. Matched
        // by externalId because a re-imported catalog has different UUIDs.
        //
        // An overlay with no matching exercise is skipped, never used to
        // invent one — a bundled exercise the app bundle does not contain is
        // not something a backup should conjure.
        for overlay in document.exerciseOverlays {
            guard
                let externalId = overlay.externalId,
                let exercise = try await exerciseRepository.fetchByExternalId(externalId)
            else {
                summary.exerciseOverlays.skipped += 1
                continue
            }
            if let notes = overlay.notes, !notes.isEmpty {
                exercise.notes = notes
            }
            if let photoURL = overlay.photoURL, !photoURL.isEmpty {
                exercise.photoURL = photoURL
            }
            try modelContext.save()
            summary.exerciseOverlays.imported += 1
        }

        try await importV5(from: document, into: &summary)
        return summary
    }

    /// formatVersion 3 data. Same rules as everything above: merge by id,
    /// never overwrite, and mark what is written `.pending` so it pushes.
    private func importV5(
        from document: BackupDocument,
        into summary: inout BackupImportSummary
    ) async throws {
        // 6. Body measurements.
        for dto in document.bodyMeasurements {
            if try await bodyMeasurementRepository.fetch(id: dto.id) != nil {
                summary.bodyMeasurements.skipped += 1
                continue
            }
            let measurement = SyncMapper.createBodyMeasurement(from: dto)
            measurement.syncStatus = .pending
            try await bodyMeasurementRepository.save(measurement)
            summary.bodyMeasurements.imported += 1
        }

        // 7. Medications, BEFORE doses, so doses can attach.
        for dto in document.medications {
            if try await medicationRepository.fetch(id: dto.id) != nil {
                summary.medications.skipped += 1
                continue
            }
            let medication = SyncMapper.createMedication(from: dto)
            medication.syncStatus = .pending
            try await medicationRepository.save(medication)
            summary.medications.imported += 1
        }

        // 8. Doses, attached to their medication — from this backup or already
        //    on the phone. One whose medication is in neither is skipped: it
        //    would be an orphan no history view can show. computedMg and the
        //    snapshotted concentration are copied as logged, never recomputed.
        for dto in document.medicationDoses {
            if try await medicationDoseRepository.fetch(id: dto.id) != nil {
                summary.medicationDoses.skipped += 1
                continue
            }
            guard let medicationId = dto.medicationId,
                  let medication = try await medicationRepository.fetch(id: medicationId) else {
                summary.medicationDoses.skipped += 1
                continue
            }
            let dose = SyncMapper.createMedicationDose(from: dto, medication: medication)
            dose.syncStatus = .pending
            try await medicationDoseRepository.save(dose)
            summary.medicationDoses.imported += 1
        }

        // 9. Alternatives, only onto a template exercise that is in a template
        //    here (templates were imported above, keeping their slot ids). An
        //    orphan would be deleted by the next template save anyway.
        let liveSlots = Set(try await templateRepository.fetchAll().flatMap { $0.exercises.map(\.id) })
        for dto in document.exerciseAlternatives {
            if try await exerciseAlternativeRepository.fetch(id: dto.id) != nil
                || !liveSlots.contains(dto.templateExerciseId) {
                summary.exerciseAlternatives.skipped += 1
                continue
            }
            let alternative = SyncMapper.createExerciseAlternative(from: dto)
            alternative.syncStatus = .pending
            try await exerciseAlternativeRepository.save(alternative)
            summary.exerciseAlternatives.imported += 1
        }

        // 10. Height — only onto a phone that has none. Never overwrites.
        if let heightCm = document.heightCm, settings.heightCm == nil {
            settings.heightCm = heightCm
            summary.heightImported = true
        }
    }

    /// Resolvability check mirroring SyncMapper's resolution order (fetch by id,
    /// then fuzzy name match), extended with the backup's own custom exercises.
    /// Throws with the full unresolved list before anything is written.
    private func preflightExerciseReferences(in document: BackupDocument) async throws {
        let bundledInBackup = Set(document.customExercises.map(\.id))
        var unresolved: [String] = []

        func check(exerciseId: UUID, name: String?) async throws {
            if bundledInBackup.contains(exerciseId) { return }
            if try await exerciseRepository.fetch(id: exerciseId) != nil { return }
            if let name, try await !exerciseRepository.fuzzySearch(query: name).isEmpty { return }
            unresolved.append(name ?? exerciseId.uuidString)
        }

        for template in document.templates
        where try await templateRepository.fetch(id: template.id) == nil {
            for te in template.exercises {
                try await check(exerciseId: te.exerciseId, name: te.exerciseName)
            }
        }
        for workout in document.workouts
        where try await workoutRepository.fetch(id: workout.id) == nil {
            for we in workout.exercises {
                try await check(exerciseId: we.exerciseId, name: we.exerciseName)
            }
        }

        guard unresolved.isEmpty else {
            throw BackupError.unresolvedExercises(unresolved)
        }
    }

    // MARK: - Exercise mapping

    /// Build and insert an `Exercise` (with fresh-id tags) into the context.
    /// Mirrors ExerciseImportService's insert-then-attach-tags pattern.
    private func insertExercise(from dto: ExerciseDTO) {
        let exercise = SyncMapper.createExercise(from: dto)
        modelContext.insert(exercise)

        var tags: [ExerciseTag] = []
        for tagDTO in dto.tags {
            let tag = ExerciseTag(category: tagDTO.category, value: tagDTO.value)
            modelContext.insert(tag)
            tags.append(tag)
        }
        exercise.tags = tags
    }
}
