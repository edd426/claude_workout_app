import Foundation
import Observation

/// What the Jefit import will do, from the dry run (#166). Counts and dates
/// only: no row of the file is ever shown or kept.
struct JefitImportOverview: Equatable, Sendable {
    enum UnitSwitch: Equatable, Sendable, CustomStringConvertible {
        case allPounds
        case allKilograms
        /// Sessions from this date on were logged in kilograms.
        case switched(Date)

        init(_ boundary: JefitUnitBoundary) {
            switch boundary {
            case .allPounds: self = .allPounds
            case .allKilograms: self = .allKilograms
            case .kilograms(let date): self = .switched(date)
            }
        }

        var description: String {
            switch self {
            case .allPounds: return "All in pounds, converted to kg"
            case .allKilograms: return "All in kilograms"
            case .switched(let date):
                return "Pounds until \(date.formatted(date: .abbreviated, time: .omitted)), then kilograms"
            }
        }
    }

    let workouts: Int
    /// Workouts not on this phone yet. Zero for a re-import: ids are derived
    /// from Jefit's own, so the same file maps to the same workouts.
    let newWorkouts: Int
    let alreadyImported: Int
    let sets: Int
    let firstWorkout: Date?
    let lastWorkout: Date?
    let unitSwitch: UnitSwitch
    /// Jefit exercise names that attach to an exercise already on the phone.
    let mappedExercises: Int
    /// Custom exercises the import creates.
    let newCustomExercises: Int
    /// One line per kind of thing left out, e.g. "1 empty session".
    let skipped: [String]

    init(plan: JefitImportPlan, existingWorkoutIds: Set<UUID>) {
        let summary = plan.summary
        workouts = summary.workouts
        alreadyImported = plan.document.workouts.filter { existingWorkoutIds.contains($0.id) }.count
        newWorkouts = plan.document.workouts.count - alreadyImported
        sets = summary.sets
        firstWorkout = summary.firstWorkoutStart
        lastWorkout = summary.lastWorkoutStart
        unitSwitch = UnitSwitch(summary.unitBoundary)
        mappedExercises = summary.resolutions.filter {
            if case .existing = $0.target { return true }
            return false
        }.count
        newCustomExercises = summary.newCustomExercises
        skipped = Self.skippedLines(summary)
    }

    private static func count(_ value: Int, _ singular: String, _ plural: String) -> String? {
        switch value {
        case 0: return nil
        case 1: return "1 \(singular)"
        default: return "\(value) \(plural)"
        }
    }

    private static func skippedLines(_ summary: JefitDryRunSummary) -> [String] {
        var lines = [
            count(summary.emptySessionsSkipped, "empty session", "empty sessions"),
            count(summary.emptyEntriesSkipped, "exercise log with no usable set", "exercise logs with no usable set"),
            count(summary.unparseableRows.count, "unreadable row", "unreadable rows"),
            count(summary.malformedSetParts, "unreadable set", "unreadable sets"),
            count(summary.emptySetsSkipped, "empty padding set", "empty padding sets"),
        ].compactMap { $0 }
        if !summary.placeholderWeights.isEmpty {
            let names = summary.placeholderWeights.map(\.jefitName).joined(separator: ", ")
            lines.append("Placeholder weight treated as bodyweight: \(names)")
        }
        if let trimmed = count(summary.longSessionsTrimmed, "session left open, ended at its last set", "sessions left open, ended at their last set") {
            lines.append(trimmed)
        }
        if !summary.skippedSections.isEmpty {
            let names = summary.skippedSections
                .map { $0.name.capitalized }
                .joined(separator: ", ")
            lines.append("Not imported: \(names)")
        }
        return lines
    }
}

/// What a finished import wrote.
struct JefitImportResult: Equatable, Sendable {
    let importedWorkouts: Int
    let skippedWorkouts: Int
    let importedCustomExercises: Int

    init(_ summary: BackupImportSummary) {
        importedWorkouts = summary.workouts.imported
        skippedWorkouts = summary.workouts.skipped
        importedCustomExercises = summary.customExercises.imported
    }

    var message: String {
        guard importedWorkouts > 0 else {
            return "Nothing new: all \(skippedWorkouts) workouts were already on this phone."
        }
        let workouts = importedWorkouts == 1 ? "1 workout" : "\(importedWorkouts) workouts"
        let customs = importedCustomExercises == 1
            ? "1 custom exercise" : "\(importedCustomExercises) custom exercises"
        var text = importedCustomExercises == 0
            ? "Imported \(workouts)."
            : "Imported \(workouts) and \(customs)."
        if skippedWorkouts > 0 {
            text += " \(skippedWorkouts) were already on this phone."
        }
        return text
    }
}

/// Drives Settings → Import Jefit history (#166): pick a file, read the dry
/// run, then import through the backup merge (never overwrites, adds
/// nothing on a re-import).
@Observable
@MainActor
final class JefitImportViewModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case ready(JefitImportOverview)
        case importing(JefitImportOverview)
        case finished(JefitImportResult)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var plan: JefitImportPlan?

    private let service: any JefitImportServiceProtocol
    private let workoutRepository: any WorkoutRepository

    init(service: any JefitImportServiceProtocol, workoutRepository: any WorkoutRepository) {
        self.service = service
        self.workoutRepository = workoutRepository
    }

    /// True when a plan with something new is on screen.
    var canImport: Bool {
        guard case .ready(let overview) = phase else { return false }
        return overview.newWorkouts > 0
    }

    /// The file picker's result. Cancelling changes nothing.
    func handlePick(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            await prepare(fileAt: url)
        case .failure(let error):
            if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return }
            phase = .failed("Couldn't open the file: \(error.localizedDescription)")
        }
    }

    func prepare(fileAt url: URL) async {
        phase = .preparing
        plan = nil
        do {
            let prepared = try await service.prepare(fileAt: url)
            let existing = Set(try await workoutRepository.fetchAll().map(\.id))
            plan = prepared
            phase = .ready(JefitImportOverview(plan: prepared, existingWorkoutIds: existing))
        } catch let error as JefitImportError {
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed("Couldn't read the file: \(error.localizedDescription)")
        }
    }

    func importPlan() async {
        guard canImport, let plan, case .ready(let overview) = phase else { return }
        phase = .importing(overview)
        do {
            phase = .finished(JefitImportResult(try await service.commit(plan)))
        } catch {
            // The merge preflights before writing, so a failure here left
            // the phone unchanged.
            phase = .failed("Import failed, nothing was changed: \(error.localizedDescription)")
        }
    }
}
