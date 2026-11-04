import Foundation

/// Backfills workout history from a Jefit export (#166) in two steps:
///
/// 1. `prepare` — parse, map and convert into a `BackupDocument`, and return
///    it with a dry-run summary. Nothing is written.
/// 2. `commit` — hand that document to `BackupService.importBackup`, the same
///    merge-by-id path a restored backup takes: exercise references are
///    preflighted before any write, existing ids are never overwritten, and
///    everything written is marked pending so it reaches the snapshot mirror.
@MainActor
protocol JefitImportServiceProtocol {
    func prepare(csv: String, options: JefitImportOptions) async throws -> JefitImportPlan
    func commit(_ plan: JefitImportPlan) async throws -> BackupImportSummary
}

extension JefitImportServiceProtocol {
    func prepare(csv: String) async throws -> JefitImportPlan {
        try await prepare(csv: csv, options: JefitImportOptions())
    }

    /// Reads a file the user picked (security-scoped URLs from
    /// `fileImporter` are handled) and prepares it.
    func prepare(fileAt url: URL, options: JefitImportOptions = JefitImportOptions()) async throws -> JefitImportPlan {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return try await prepare(csv: text, options: options)
    }
}

@MainActor
final class JefitImportService: JefitImportServiceProtocol {
    private let exerciseRepository: any ExerciseRepository
    private let backupService: any BackupServiceProtocol
    private let mapTable: JefitExerciseMapTable
    private let temporaryDirectory: URL

    init(
        exerciseRepository: any ExerciseRepository,
        backupService: any BackupServiceProtocol,
        mapTable: JefitExerciseMapTable,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.exerciseRepository = exerciseRepository
        self.backupService = backupService
        self.mapTable = mapTable
        self.temporaryDirectory = temporaryDirectory
    }

    func prepare(csv: String, options: JefitImportOptions) async throws -> JefitImportPlan {
        let localExercises = try await exerciseRepository.fetchAll().map(JefitLocalExercise.init)
        let table = mapTable
        // Parsing and converting a ~1 MB export is pure CPU work; keep it off
        // the main actor.
        return try await Task.detached(priority: .userInitiated) {
            let export = try JefitExport.parse(csv)
            let mapper = JefitExerciseMapper(table: table, localExercises: localExercises)
            return JefitConverter.convert(export, mapper: mapper, options: options)
        }.value
    }

    func commit(_ plan: JefitImportPlan) async throws -> BackupImportSummary {
        // Through a file, exactly as a restored backup arrives: the document
        // takes the same decode → preflight → merge path, unchanged.
        let url = temporaryDirectory.appending(path: "jefit-import-\(UUID().uuidString).json")
        try JSONEncoder().encode(plan.document).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await backupService.importBackup(from: url)
    }
}
