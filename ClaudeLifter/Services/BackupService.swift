import Foundation
import SwiftData

// MARK: - Backup wire format

/// A device-local JSON backup: everything the user would lose if the store were
/// wiped and cloud sync had never run. Bundled (non-custom) exercises are omitted
/// — they re-import from the app bundle — so only `isCustom` exercises are carried.
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
}

// MARK: - Service

@MainActor
protocol BackupServiceProtocol {
    /// Encode all workouts, templates, custom exercises, and preferences into a
    /// JSON file in the app's Documents directory and return its URL.
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
    private let documentsDirectory: URL

    init(
        modelContext: ModelContext,
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository,
        preferenceRepository: any TrainingPreferenceRepository,
        documentsDirectory: URL = URL.documentsDirectory
    ) {
        self.modelContext = modelContext
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
        self.preferenceRepository = preferenceRepository
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

        let document = BackupDocument(
            formatVersion: 1,
            exportedAt: .now,
            workouts: workouts,
            templates: templates,
            customExercises: customExercises,
            preferences: preferences
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

        return summary
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
