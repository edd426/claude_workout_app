import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Locates a real Jefit export on the developer's Mac, if there is one. The
/// repo is public: the export itself is never committed, and nothing here
/// names a user. `JEFIT_EXPORT_PATH` (passed as
/// `TEST_RUNNER_JEFIT_EXPORT_PATH` to xcodebuild) wins; otherwise the newest
/// CSV in `~/Documents/Analysis/fitness_and_wellness/jefit_export` on the
/// simulator's host.
enum JefitRealExport {
    static func url() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["JEFIT_EXPORT_PATH"], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let home = hostHome(environment) else { return nil }
        let folder = URL(fileURLWithPath: home)
            .appending(path: "Documents/Analysis/fitness_and_wellness/jefit_export")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "csv" }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func hostHome(_ environment: [String: String]) -> String? {
        if let home = environment["SIMULATOR_HOST_HOME"] { return home }
        // Simulator homes live under the host home's Library/Developer.
        let home = NSHomeDirectory()
        guard let range = home.range(of: "/Library/Developer/CoreSimulator") else { return nil }
        return String(home[..<range.lowerBound])
    }

    static var isAvailable: Bool { url() != nil }
    static var fullImportRequested: Bool {
        ProcessInfo.processInfo.environment["JEFIT_FULL_IMPORT"] == "1"
    }
}

/// Runs only where a real export exists; skipped everywhere else (CI, other
/// machines). Prints aggregate counts and exercise names only — never a row.
@Suite("Jefit real export dry run (local only)")
@MainActor
struct JefitRealExportDryRunTests {

    @Test("Dry run of the real export: aggregates only", .enabled(if: JefitRealExport.isAvailable))
    func dryRun() async throws {
        let url = try #require(JefitRealExport.url())
        let container = try makeTestContainer()
        let context = container.mainContext
        let catalogURL = try #require(Bundle.main.url(forResource: "exercises", withExtension: "json"))
        try await ExerciseImportService().importExercises(from: Data(contentsOf: catalogURL), into: context)

        let exercises = SwiftDataExerciseRepository(context: context)
        let workouts = SwiftDataWorkoutRepository(context: context)
        let backup = BackupService(
            modelContext: context,
            workoutRepository: workouts,
            templateRepository: SwiftDataTemplateRepository(context: context),
            exerciseRepository: exercises,
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            bodyMeasurementRepository: SwiftDataBodyMeasurementRepository(context: context),
            medicationRepository: SwiftDataMedicationRepository(context: context),
            medicationDoseRepository: SwiftDataMedicationDoseRepository(context: context),
            exerciseAlternativeRepository: SwiftDataExerciseAlternativeRepository(context: context),
            settings: SettingsManager(defaults: UserDefaults(suiteName: "jefit-real-\(UUID())")!),
            documentsDirectory: FileManager.default.temporaryDirectory
        )
        let service = JefitImportService(
            exerciseRepository: exercises,
            backupService: backup,
            mapTable: try JefitExerciseMapTable.bundled()
        )

        let started = Date()
        let plan = try await service.prepare(fileAt: url)
        let prepareSeconds = Date().timeIntervalSince(started)
        report(plan.summary, prepareSeconds: prepareSeconds)

        #expect(plan.summary.workouts > 0)
        #expect(plan.summary.sets > 0)

        guard JefitRealExport.fullImportRequested else { return }
        let importStart = Date()
        let first = try await service.commit(plan)
        let importSeconds = Date().timeIntervalSince(importStart)
        let second = try await service.commit(try await service.prepare(fileAt: url))
        let storedSets = try await workouts.fetchAll().reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
        print("JEFIT-DRYRUN: full import: workouts imported=\(first.workouts.imported) skipped=\(first.workouts.skipped); customExercises imported=\(first.customExercises.imported); seconds=\(String(format: "%.1f", importSeconds))")
        print("JEFIT-DRYRUN: re-import: workouts imported=\(second.workouts.imported) skipped=\(second.workouts.skipped); customExercises imported=\(second.customExercises.imported)")
        print("JEFIT-DRYRUN: stored sets after import=\(storedSets)")
        #expect(first.workouts.imported == plan.summary.workouts)
        #expect(second.workouts.imported == 0)
        #expect(storedSets == plan.summary.sets)
    }

    private func report(_ summary: JefitDryRunSummary, prepareSeconds: TimeInterval) {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        func text(_ date: Date?) -> String { date.map(day.string(from:)) ?? "-" }

        let boundary: String
        switch summary.unitBoundary {
        case .allPounds: boundary = "all pounds"
        case .allKilograms: boundary = "all kilograms"
        case .kilograms(let date): boundary = "kg from \(ISO8601DateFormatter().string(from: date))"
        }
        let methods = Dictionary(grouping: summary.resolutions, by: \.method).mapValues(\.count)
        let catalogEntries = summary.catalogNames.reduce(0) { $0 + $1.entries }
        let customEntries = summary.customNames.reduce(0) { $0 + $1.entries }
        let newCustom = summary.customNames.filter { if case .newCustom = $0.target { return true } else { return false } }

        var lines = [
            "workouts=\(summary.workouts) exerciseEntries=\(summary.exerciseEntries) sets=\(summary.sets)",
            "dateRange=\(text(summary.firstWorkoutStart))..\(text(summary.lastWorkoutStart))",
            "unitBoundary=\(boundary) poundWorkouts=\(summary.poundWorkouts) kilogramWorkouts=\(summary.kilogramWorkouts)",
            "unitEvidence: lbSetLogs=\(summary.unitEvidence.poundSetLogs) kgSetLogs=\(summary.unitEvidence.kilogramSetLogs) contradicting=\(summary.unitEvidence.contradictingSetLogs) continuityJumps=\(summary.unitEvidence.continuityJumps)",
            "names=\(summary.resolutions.count) catalog=\(summary.catalogNames.count) custom=\(summary.customNames.count) (via new=\(newCustom.count)) unmapped=\(summary.unmappedNames.count)",
            "distinctTargets: catalog=\(Set(summary.catalogNames.map(\.target.name)).count) custom=\(Set(summary.customNames.map(\.target.name)).count) newCustomExercises=\(summary.newCustomExercises)",
            "methods: exact=\(methods[.exact] ?? 0) table=\(methods[.table] ?? 0) normalized=\(methods[.normalized] ?? 0) unmapped=\(methods[.unmapped] ?? 0)",
            "entries: catalog=\(catalogEntries) custom=\(customEntries)",
            "unparseableRows=\(summary.unparseableRows.count) malformedSetParts=\(summary.malformedSetParts) emptySetsSkipped=\(summary.emptySetsSkipped) emptyEntriesSkipped=\(summary.emptyEntriesSkipped)",
            "emptySessionsSkipped=\(summary.emptySessionsSkipped) orphanSessions=\(summary.orphanSessions) longSessionsTrimmed=\(summary.longSessionsTrimmed)",
            "placeholderWeights=" + summary.placeholderWeights.map { "\($0.jefitName)(\($0.loggedWeight)x\($0.sets))" }.joined(separator: "; "),
            "skippedSections=" + summary.skippedSections.map { "\($0.name):\($0.rows)" }.joined(separator: ", "),
            "estimatedSnapshotGrowthBytes=\(summary.estimatedSnapshotGrowthBytes)",
            "prepareSeconds=\(String(format: "%.2f", prepareSeconds))",
        ]
        // Top custom exercises by target (several Jefit names can share one).
        let byTarget = Dictionary(grouping: summary.customNames, by: \.target.name)
            .map { (name: $0.key, entries: $0.value.reduce(0) { $0 + $1.entries }, sets: $0.value.reduce(0) { $0 + $1.sets }) }
            .sorted { ($0.entries, $1.name) > ($1.entries, $0.name) }
        lines += byTarget.prefix(20).enumerated().map { index, target in
            "topCustom[\(index + 1)]=\(target.name) entries=\(target.entries) sets=\(target.sets)"
        }
        lines += summary.unmappedNames.map { "unmapped=\($0.jefitName) entries=\($0.entries)" }
        for line in lines { print("JEFIT-DRYRUN: \(line)") }
    }
}
