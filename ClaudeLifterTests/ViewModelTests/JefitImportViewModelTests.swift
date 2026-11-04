import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// The Jefit import screen's states (#166). Synthetic fixtures only: the
/// real export never enters the repo.
@Suite("JefitImportViewModel (#166)")
@MainActor
struct JefitImportViewModelTests {

    /// Keeps the container alive for as long as its context is used.
    struct Harness {
        let container: ModelContainer
        let workouts: SwiftDataWorkoutRepository
        let service: JefitImportService
        let viewModel: JefitImportViewModel
    }

    private func makeHarness() throws -> Harness {
        let container = try makeTestContainer()
        let context = container.mainContext
        for exercise in [
            Exercise(name: "Barbell Squat", isCustom: false, externalId: "Barbell_Squat"),
            Exercise(name: "Crunches", isCustom: false, externalId: "Crunches"),
            Exercise(name: "Pushups", isCustom: false, externalId: "Pushups"),
            Exercise(name: "Plank", isCustom: false, externalId: "Plank"),
        ] {
            context.insert(exercise)
        }
        try context.save()
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
            settings: SettingsManager(defaults: UserDefaults(suiteName: "jefit-vm-\(UUID())")!),
            documentsDirectory: FileManager.default.temporaryDirectory
        )
        let service = JefitImportService(
            exerciseRepository: exercises,
            backupService: backup,
            mapTable: try JefitExerciseMapTable.bundled()
        )
        return Harness(
            container: container,
            workouts: workouts,
            service: service,
            viewModel: JefitImportViewModel(service: service, workoutRepository: workouts)
        )
    }

    private func writeFile(_ text: String, name: String = "jefit-export.csv") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "jefit-vm-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func overview(_ vm: JefitImportViewModel) throws -> JefitImportOverview {
        guard case .ready(let overview) = vm.phase else {
            Issue.record("expected .ready, got \(vm.phase)")
            throw CancellationError()
        }
        return overview
    }

    // MARK: - Plan

    @Test("Picking a Jefit export shows the plan summary")
    func planSummary() async throws {
        let harness = try makeHarness()
        let vm = harness.viewModel

        await vm.prepare(fileAt: try writeFile(JefitFixtures.export))

        let plan = try overview(vm)
        #expect(plan.workouts == 5)
        #expect(plan.newWorkouts == 5)
        #expect(plan.alreadyImported == 0)
        #expect(plan.sets == 24)
        #expect(plan.firstWorkout == Date(timeIntervalSince1970: JefitFixtures.s1Start))
        #expect(plan.lastWorkout == Date(timeIntervalSince1970: JefitFixtures.orphanLogTime))
        #expect(plan.unitSwitch == .switched(Date(timeIntervalSince1970: JefitFixtures.s4Start)))
        #expect(plan.mappedExercises == 4)
        #expect(plan.newCustomExercises == 2)
    }

    @Test("The plan lists what it skips")
    func planSkips() async throws {
        let harness = try makeHarness()
        let vm = harness.viewModel

        await vm.prepare(fileAt: try writeFile(JefitFixtures.export))

        let skipped = try overview(vm).skipped
        #expect(skipped.contains("1 empty session"))
        #expect(skipped.contains("1 unreadable row"))
        #expect(skipped.contains("1 unreadable set"))
        #expect(skipped.contains("2 empty padding sets"))
        #expect(skipped.contains { $0.hasPrefix("Not imported: ") && $0.contains("Cardio Logs") })
    }

    @Test("Import writes the workouts and reports the result")
    func importReportsResult() async throws {
        let harness = try makeHarness()
        let vm = harness.viewModel
        await vm.prepare(fileAt: try writeFile(JefitFixtures.export))

        await vm.importPlan()

        guard case .finished(let result) = vm.phase else {
            Issue.record("expected .finished, got \(vm.phase)")
            return
        }
        #expect(result.importedWorkouts == 5)
        #expect(result.skippedWorkouts == 0)
        #expect(result.importedCustomExercises == 2)
        #expect(result.message == "Imported 5 workouts and 2 custom exercises.")
        #expect(try await harness.workouts.fetchAll().count == 5)
    }

    @Test("A re-import finds everything already on the phone and reports 0 new")
    func reimportReportsNothingNew() async throws {
        let harness = try makeHarness()
        let url = try writeFile(JefitFixtures.export)
        await harness.viewModel.prepare(fileAt: url)
        await harness.viewModel.importPlan()

        let again = JefitImportViewModel(service: harness.service, workoutRepository: harness.workouts)
        await again.prepare(fileAt: url)

        let plan = try overview(again)
        #expect(plan.newWorkouts == 0)
        #expect(plan.alreadyImported == 5)
        #expect(!again.canImport)

        await again.importPlan()
        #expect(try overview(again).newWorkouts == 0)
        #expect(try await harness.workouts.fetchAll().count == 5)
    }

    @Test("A commit that adds nothing says so")
    func nothingNewMessage() {
        var summary = BackupImportSummary()
        summary.workouts = .init(imported: 0, skipped: 5)
        summary.customExercises = .init(imported: 0, skipped: 2)

        let result = JefitImportResult(summary)

        #expect(result.message == "Nothing new: all 5 workouts were already on this phone.")
    }

    @Test("No new custom exercises leaves them out of the message")
    func noCustomExercisesMessage() {
        var summary = BackupImportSummary()
        summary.workouts = .init(imported: 3, skipped: 0)

        #expect(JefitImportResult(summary).message == "Imported 3 workouts.")
    }

    @Test("A partial overlap reports both counts")
    func partialOverlapMessage() {
        var summary = BackupImportSummary()
        summary.workouts = .init(imported: 3, skipped: 2)
        summary.customExercises = .init(imported: 1, skipped: 0)

        let result = JefitImportResult(summary)

        #expect(result.message == "Imported 3 workouts and 1 custom exercise. 2 were already on this phone.")
    }

    // MARK: - Errors and cancel

    @Test("A file that isn't a Jefit export fails with an explanation")
    func wrongFile() async throws {
        let harness = try makeHarness()
        let vm = harness.viewModel

        await vm.prepare(fileAt: try writeFile("date,weight\n2024-01-01,80\n", name: "other.csv"))

        guard case .failed(let message) = vm.phase else {
            Issue.record("expected .failed, got \(vm.phase)")
            return
        }
        #expect(message.contains("doesn't look like a Jefit export"))
        #expect(!vm.canImport)
    }

    @Test("Cancelling the file picker leaves the screen as it was")
    func cancelledPick() async throws {
        let harness = try makeHarness()
        let vm = harness.viewModel

        await vm.handlePick(.failure(CocoaError(.userCancelled)))

        #expect(vm.phase == .idle)
    }

    @Test("A picker error is shown")
    func pickerError() async throws {
        let harness = try makeHarness()
        let vm = harness.viewModel

        await vm.handlePick(.failure(CocoaError(.fileReadNoPermission)))

        guard case .failed = vm.phase else {
            Issue.record("expected .failed, got \(vm.phase)")
            return
        }
    }

    @Test("A picked file is prepared")
    func pickedFileIsPrepared() async throws {
        let harness = try makeHarness()
        let vm = harness.viewModel

        await vm.handlePick(.success([try writeFile(JefitFixtures.export)]))

        #expect(try overview(vm).workouts == 5)
    }

    @Test("Import is only offered once a plan is ready")
    func importNeedsPlan() async throws {
        let harness = try makeHarness()
        let vm = harness.viewModel

        #expect(!vm.canImport)
        await vm.importPlan()

        #expect(vm.phase == .idle)
        #expect(try await harness.workouts.fetchAll().isEmpty)
    }

    @Test("Unit switch wording", arguments: [
        (JefitUnitBoundary.allPounds, "All in pounds, converted to kg"),
        (JefitUnitBoundary.allKilograms, "All in kilograms"),
    ])
    func unitWording(boundary: JefitUnitBoundary, expected: String) {
        #expect(JefitImportOverview.UnitSwitch(boundary).description == expected)
    }
}
