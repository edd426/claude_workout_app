import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("JefitImportService (#166)")
@MainActor
struct JefitImportServiceTests {

    /// Keeps the container alive for as long as its context is used (iOS 26
    /// traps when a context outlives its container).
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let exercises: SwiftDataExerciseRepository
        let workouts: SwiftDataWorkoutRepository
        let service: JefitImportService
        let squat: Exercise
    }

    private func makeHarness(existingSingleLegPress: Bool = false) throws -> Harness {
        let container = try makeTestContainer()
        let context = container.mainContext
        let squat = Exercise(name: "Barbell Squat", isCustom: false, externalId: "Barbell_Squat")
        for exercise in [
            squat,
            Exercise(name: "Crunches", isCustom: false, externalId: "Crunches"),
            Exercise(name: "Pushups", isCustom: false, externalId: "Pushups"),
            Exercise(name: "Plank", isCustom: false, externalId: "Plank"),
        ] {
            context.insert(exercise)
        }
        if existingSingleLegPress {
            let id = UUID()
            context.insert(Exercise(
                id: id,
                name: "Single-Leg Press",
                isCustom: true,
                externalId: "custom:single-leg-press:\(id.uuidString.lowercased())"
            ))
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
            settings: SettingsManager(defaults: UserDefaults(suiteName: "jefit-tests-\(UUID())")!),
            documentsDirectory: FileManager.default.temporaryDirectory
        )
        let service = JefitImportService(
            exerciseRepository: exercises,
            backupService: backup,
            mapTable: try JefitExerciseMapTable.bundled()
        )
        return Harness(
            container: container, context: context, exercises: exercises,
            workouts: workouts, service: service, squat: squat
        )
    }

    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private func workout(_ sessionId: String, in plan: JefitImportPlan) throws -> WorkoutDTO {
        try #require(plan.document.workouts.first { $0.id == JefitConverter.stableId("jefit-session-\(sessionId)") })
    }

    // MARK: - Dry run

    @Test("Dry run counts sessions, entries and sets, and reports what it skipped")
    func dryRunCounts() async throws {
        let harness = try makeHarness()
        let summary = try await harness.service.prepare(csv: JefitFixtures.export).summary

        #expect(summary.workouts == 5)          // S1, S2, S4, S5 + one orphan group
        #expect(summary.exerciseEntries == 13)
        #expect(summary.sets == 24)
        #expect(summary.emptySessionsSkipped == 1)
        #expect(summary.orphanSessions == 1)
        #expect(summary.malformedSetParts == 1)
        #expect(summary.emptySetsSkipped == 2)
        #expect(summary.unparseableRows.count == 1)
        #expect(summary.firstWorkoutStart == date(JefitFixtures.s1Start))
        #expect(summary.lastWorkoutStart == date(JefitFixtures.orphanLogTime))
        #expect(summary.skippedSections.contains(JefitSkippedSection(name: "CARDIO LOGS", rows: 1)))
    }

    @Test("Dry run detects the lb→kg boundary at the first kilogram session")
    func detectsBoundary() async throws {
        let harness = try makeHarness()
        let summary = try await harness.service.prepare(csv: JefitFixtures.export).summary
        #expect(summary.unitBoundary == .kilograms(from: date(JefitFixtures.s4Start)))
        #expect(summary.unitBoundaryOverridden == false)
        #expect(summary.unitEvidence.poundSetLogs == 1)
        #expect(summary.unitEvidence.kilogramSetLogs == 2)
        #expect(summary.unitEvidence.contradictingSetLogs == 0)
        #expect(summary.poundWorkouts == 2)
        #expect(summary.kilogramWorkouts == 3)
    }

    @Test("An overridden boundary is used and its contradictions are reported")
    func overrideBoundary() async throws {
        let harness = try makeHarness()
        var options = JefitImportOptions()
        options.unitBoundaryOverride = .allPounds
        let plan = try await harness.service.prepare(csv: JefitFixtures.export, options: options)

        #expect(plan.summary.unitBoundary == .allPounds)
        #expect(plan.summary.unitBoundaryOverridden)
        #expect(plan.summary.unitEvidence.contradictingSetLogs == 2)
        let squat = try #require(try workout("1004", in: plan).exercises.first)
        #expect(squat.sets.map(\.weight) == [45.36, 46.49])
    }

    // MARK: - Conversion

    @Test("Weights are stored in kilograms; bodyweight and Jefit's placeholder weight become nil")
    func weights() async throws {
        let harness = try makeHarness()
        let plan = try await harness.service.prepare(csv: JefitFixtures.export)

        let s1 = try workout("1001", in: plan)
        #expect(s1.exercises[0].sets.map(\.weight) == [102.06, 106.59])
        #expect(s1.exercises[2].sets.map(\.weight) == [nil, nil])      // Push Up 0x15
        #expect(s1.exercises[2].sets.map(\.reps) == [15, 12])
        #expect(s1.exercises[3].sets.map(\.weight) == [nil, nil, nil]) // Crunch 10x20 placeholder
        #expect(try workout("1004", in: plan).exercises[0].sets.map(\.weight) == [100, 102.5])
        #expect(try workout("1005", in: plan).exercises[0].sets.map(\.weight) == [60, 105])

        let units = Set(plan.document.workouts.flatMap { $0.exercises.flatMap { $0.sets.map(\.weightUnit) } })
        #expect(units == ["kg"])
        #expect(plan.summary.placeholderWeights == [
            JefitPlaceholderWeight(jefitName: "Crunch", loggedWeight: 10, sets: 5),
        ])
    }

    @Test("Workouts are completed, tagged as imported, and timed from the session")
    func workoutShape() async throws {
        let harness = try makeHarness()
        let plan = try await harness.service.prepare(csv: JefitFixtures.export)

        let s1 = try workout("1001", in: plan)
        #expect(s1.startedAt == date(JefitFixtures.s1Start))
        #expect(s1.completedAt == date(JefitFixtures.s1Start + 3600))
        #expect(s1.notes == JefitImportOptions.importNote)
        #expect(s1.templateId == nil)
        // S4 has no end time: start + total_time.
        #expect(try workout("1004", in: plan).completedAt == date(JefitFixtures.s4Start + 2700))

        for workout in plan.document.workouts {
            let completedAt = try #require(workout.completedAt)
            for set in workout.exercises.flatMap(\.sets) {
                #expect(set.isCompleted)
                let setTime = try #require(set.completedAt)
                #expect(setTime >= workout.startedAt && setTime <= completedAt)
            }
        }
    }

    @Test("Exercises keep Jefit's log order; sets are numbered from 0 without gaps")
    func ordering() async throws {
        let harness = try makeHarness()
        let s2 = try workout("1002", in: try await harness.service.prepare(csv: JefitFixtures.export))
        #expect(s2.exercises.map(\.order) == [0, 1, 2, 3])
        #expect(s2.exercises.map(\.exerciseName) == ["Barbell Squat", "Zorbo Press", "Plank", "Crunches"])
        #expect(s2.exercises[1].sets.map(\.order) == [0, 1])          // abcx5 dropped
        #expect(s2.exercises[1].sets.map(\.reps) == [8, 8])
        #expect(s2.exercises[2].sets.map(\.reps) == [45])             // 0x0 padding dropped
        #expect(s2.exercises[3].notes == "Jefit: Crunch")
        #expect(s2.exercises[0].notes == nil)
    }

    @Test("An unmapped Jefit exercise becomes a custom exercise with a custom: externalId")
    func unmappedBecomesCustom() async throws {
        let harness = try makeHarness()
        let plan = try await harness.service.prepare(csv: JefitFixtures.export)

        let zorbo = try #require(plan.document.customExercises.first { $0.name == "Zorbo Press" })
        #expect(zorbo.isCustom)
        #expect(zorbo.externalId == "custom:zorbo-press:\(zorbo.id.uuidString.lowercased())")
        #expect(try workout("1002", in: plan).exercises[1].exerciseId == zorbo.id)
        #expect(plan.document.customExercises.map(\.name) == ["Single-Leg Press", "Zorbo Press"])
        #expect(plan.summary.newCustomExercises == 2)

        let resolution = try #require(plan.summary.resolutions.first { $0.jefitName == "Zorbo Press" })
        #expect(resolution.method == .unmapped)
        #expect(resolution.entries == 2)
        #expect(plan.summary.unmappedNames.map(\.jefitName) == ["Zorbo Press"])
    }

    @Test("History for a mapped custom name attaches to the phone's existing custom exercise")
    func reusesExistingCustom() async throws {
        let harness = try makeHarness(existingSingleLegPress: true)
        let existing = try #require(try await harness.exercises.fetchAll().first { $0.name == "Single-Leg Press" })
        let plan = try await harness.service.prepare(csv: JefitFixtures.export)

        #expect(plan.document.customExercises.map(\.name) == ["Zorbo Press"])
        #expect(try workout("1001", in: plan).exercises[1].exerciseId == existing.id)
    }

    @Test("Converting the same export twice yields an identical document")
    func deterministic() async throws {
        let harness = try makeHarness()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(try await harness.service.prepare(csv: JefitFixtures.export).document)
        let second = try encoder.encode(try await harness.service.prepare(csv: JefitFixtures.export).document)
        #expect(first == second)
    }

    @Test("The dry run writes nothing")
    func dryRunWritesNothing() async throws {
        let harness = try makeHarness()
        let before = try await harness.exercises.fetchCount()
        _ = try await harness.service.prepare(csv: JefitFixtures.export)
        #expect(try await harness.workouts.fetchAll().isEmpty)
        #expect(try await harness.exercises.fetchCount() == before)
    }

    @Test("The estimated snapshot growth is the wire size of the new records")
    func snapshotGrowth() async throws {
        let harness = try makeHarness()
        let plan = try await harness.service.prepare(csv: JefitFixtures.export)
        let encoder = NetworkService.makeWireEncoder()
        let expected = try encoder.encode(plan.document.workouts).count
            + encoder.encode(plan.document.customExercises).count
        #expect(plan.summary.estimatedSnapshotGrowthBytes == expected)
    }

    // MARK: - Commit through the backup import

    @Test("The document passes the backup preflight and imports; importing again adds nothing")
    func commitIsIdempotent() async throws {
        let harness = try makeHarness()

        let first = try await harness.service.commit(try await harness.service.prepare(csv: JefitFixtures.export))
        #expect(first.workouts.imported == 5)
        #expect(first.customExercises.imported == 2)

        let second = try await harness.service.commit(try await harness.service.prepare(csv: JefitFixtures.export))
        #expect(second.workouts.imported == 0)
        #expect(second.workouts.skipped == 5)
        #expect(second.customExercises.imported == 0)

        let stored = try await harness.workouts.fetchAll()
        #expect(stored.count == 5)
        #expect(stored.flatMap { $0.exercises.flatMap(\.sets) }.count == 24)
        #expect(stored.allSatisfy { $0.notes == JefitImportOptions.importNote && $0.completedAt != nil })
        // Restored records are local changes: they must push on the next sync.
        #expect(try await harness.workouts.fetchPending().count == 5)
    }

    @Test("Autofill still uses the most recent session after older history is imported")
    func autofillUsesMostRecent() async throws {
        let harness = try makeHarness()
        let recent = Workout(
            name: "Lower A",
            startedAt: date(1_790_000_000),
            completedAt: date(1_790_003_000)
        )
        harness.context.insert(recent)
        let entry = WorkoutExercise(order: 0, exercise: harness.squat)
        harness.context.insert(entry)
        recent.exercises.append(entry)
        let set = WorkoutSet(order: 0, weight: 60, weightUnit: .kg, reps: 8, isCompleted: true, completedAt: date(1_790_001_000))
        harness.context.insert(set)
        entry.sets.append(set)
        try harness.context.save()

        _ = try await harness.service.commit(try await harness.service.prepare(csv: JefitFixtures.export))

        let autofill = AutoFillService(workoutRepository: harness.workouts)
        let last = try #require(try await autofill.lastPerformed(exerciseId: harness.squat.id))
        #expect(last.weight == 60)
        #expect(last.reps == 8)
        #expect(last.date == date(1_790_001_000))
    }
}
