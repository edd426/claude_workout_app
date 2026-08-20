import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("BackupService Tests")
@MainActor
struct BackupServiceTests {

    // MARK: - Helpers

    /// Identifiers of the records planted by `seed`, so tests can assert the
    /// exact objects survived a round-trip rather than merely counting rows.
    private struct SeedIDs {
        let workoutId: UUID
        let templateId: UUID
        let customExerciseId: UUID
        let bundledExerciseId: UUID
        let preferenceKey: String
    }

    private func makeService(
        context: ModelContext,
        documentsDirectory: URL
    ) -> BackupService {
        BackupService(
            modelContext: context,
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            documentsDirectory: documentsDirectory
        )
    }

    /// Plant one custom exercise (with a tag), one bundled exercise, a workout
    /// with two completed sets and a template — both referencing the *custom*
    /// exercise so they survive an import into a container that only receives
    /// custom exercises — plus one training preference.
    @discardableResult
    private func seed(into context: ModelContext) throws -> SeedIDs {
        // Custom exercise with a tag.
        let custom = Exercise(
            name: "Custom Cable Fly",
            equipment: "cable",
            primaryMuscles: ["chest"],
            isCustom: true,
            externalId: nil,
            notes: "Seat pin 4"
        )
        context.insert(custom)
        let tag = ExerciseTag(category: "muscle_group", value: "chest")
        context.insert(tag)
        custom.tags = [tag]

        // Bundled (non-custom) exercise — must NOT be exported.
        let bundled = Exercise(name: "Barbell Bench Press", isCustom: false)
        context.insert(bundled)

        // Workout referencing the custom exercise, with two completed sets.
        let workout = Workout(
            name: "Push Day",
            startedAt: Date(timeIntervalSinceNow: -3600),
            completedAt: Date(timeIntervalSinceNow: -600)
        )
        context.insert(workout)
        let we = WorkoutExercise(order: 0, exercise: custom)
        context.insert(we)
        workout.exercises.append(we)
        let set1 = WorkoutSet(order: 0, weight: 30, weightUnit: .kg, reps: 12, isCompleted: true, completedAt: Date())
        let set2 = WorkoutSet(order: 1, weight: 32.5, weightUnit: .kg, reps: 10, isCompleted: true, completedAt: Date())
        context.insert(set1)
        context.insert(set2)
        we.sets.append(set1)
        we.sets.append(set2)

        // Template referencing the custom exercise.
        let template = WorkoutTemplate(name: "Chest Day")
        context.insert(template)
        let te = TemplateExercise(order: 0, exercise: custom, defaultSets: 3, defaultReps: 12)
        context.insert(te)
        template.exercises.append(te)

        // Preference.
        let pref = TrainingPreference(key: "training_style", value: "hypertrophy", source: "user_stated")
        context.insert(pref)

        try context.save()

        return SeedIDs(
            workoutId: workout.id,
            templateId: template.id,
            customExerciseId: custom.id,
            bundledExerciseId: bundled.id,
            preferenceKey: pref.key
        )
    }

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "backup-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Export

    @Test("Export produces a decodable BackupDocument with correct counts, excluding non-custom exercises")
    func exportProducesDecodableDocumentWithCounts() async throws {
        // Arrange
        let container = try makeTestContainer()
        let context = container.mainContext
        _ = try seed(into: context)
        let service = makeService(context: context, documentsDirectory: try tempDirectory())

        // Act
        let url = try await service.exportBackup()
        let data = try Data(contentsOf: url)
        let doc = try JSONDecoder().decode(BackupDocument.self, from: data)

        // Assert
        // 2 since #140 — the file now also carries bundled-exercise user data.
        #expect(doc.formatVersion == 2)
        #expect(doc.workouts.count == 1)
        #expect(doc.templates.count == 1)
        #expect(doc.preferences.count == 1)
        // Custom-only: the bundled exercise must be absent.
        #expect(doc.customExercises.count == 1)
        #expect(doc.customExercises.allSatisfy { $0.isCustom })
        #expect(doc.customExercises.first?.name == "Custom Cable Fly")
        #expect(doc.customExercises.first?.notes == "Seat pin 4")
    }

    // MARK: - Round-trip

    @Test("Round-trip export then import into a fresh container restores workouts with sets, templates, and preferences")
    func roundTripRestoresData() async throws {
        // Arrange — container A: seed + export
        let containerA = try makeTestContainer()
        let contextA = containerA.mainContext
        let ids = try seed(into: contextA)
        let serviceA = makeService(context: contextA, documentsDirectory: try tempDirectory())
        let url = try await serviceA.exportBackup()

        // Arrange — container B: fresh (custom exercise ids absent)
        let containerB = try makeTestContainer()
        let contextB = containerB.mainContext
        let serviceB = makeService(context: contextB, documentsDirectory: try tempDirectory())

        // Act
        let summary = try await serviceB.importBackup(from: url)

        // Assert — summary
        #expect(summary.customExercises.imported == 1)
        #expect(summary.templates.imported == 1)
        #expect(summary.workouts.imported == 1)
        #expect(summary.preferences.imported == 1)

        // Assert — workouts arrive with exercises AND sets
        let workouts = try await SwiftDataWorkoutRepository(context: contextB).fetchAll()
        #expect(workouts.count == 1)
        let workout = try #require(workouts.first)
        #expect(workout.id == ids.workoutId)
        #expect(workout.exercises.count == 1)
        let we = try #require(workout.exercises.first)
        #expect(we.exercise != nil)
        #expect(we.exercise?.id == ids.customExerciseId)
        #expect(we.sets.count == 2)

        // Assert — templates with exercises
        let templates = try await SwiftDataTemplateRepository(context: contextB).fetchAll()
        #expect(templates.count == 1)
        #expect(templates.first?.id == ids.templateId)
        #expect(templates.first?.exercises.count == 1)

        // Assert — preferences present
        let prefs = try await SwiftDataTrainingPreferenceRepository(context: contextB).fetchAll()
        #expect(prefs.count == 1)
        #expect(prefs.first?.key == ids.preferenceKey)

        // Assert — custom exercise present
        let exercises = try await SwiftDataExerciseRepository(context: contextB).fetchAll()
        #expect(exercises.contains { $0.id == ids.customExerciseId })
    }

    // MARK: - Skip existing

    @Test("Importing the same backup twice skips existing records with no duplicates")
    func importSkipsExistingRecords() async throws {
        // Arrange
        let containerA = try makeTestContainer()
        let contextA = containerA.mainContext
        _ = try seed(into: contextA)
        let serviceA = makeService(context: contextA, documentsDirectory: try tempDirectory())
        let url = try await serviceA.exportBackup()

        let containerB = try makeTestContainer()
        let contextB = containerB.mainContext
        let serviceB = makeService(context: contextB, documentsDirectory: try tempDirectory())

        // Act — import twice
        _ = try await serviceB.importBackup(from: url)
        let second = try await serviceB.importBackup(from: url)

        // Assert — everything skipped on the second pass
        #expect(second.customExercises.imported == 0)
        #expect(second.customExercises.skipped == 1)
        #expect(second.templates.imported == 0)
        #expect(second.templates.skipped == 1)
        #expect(second.workouts.imported == 0)
        #expect(second.workouts.skipped == 1)
        #expect(second.preferences.imported == 0)
        #expect(second.preferences.skipped == 1)

        // Assert — no duplicates
        let workoutCount = try await SwiftDataWorkoutRepository(context: contextB).fetchAll().count
        #expect(workoutCount == 1)
        let templateCount = try await SwiftDataTemplateRepository(context: contextB).fetchAll().count
        #expect(templateCount == 1)
        let prefCount = try await SwiftDataTrainingPreferenceRepository(context: contextB).fetchAll().count
        #expect(prefCount == 1)
        let customCount = try await SwiftDataExerciseRepository(context: contextB).fetchAll().filter { $0.isCustom }.count
        #expect(customCount == 1)
    }

    // MARK: - Pending sync status

    @Test("Imported records have pending sync status so they push to Azure")
    func importedRecordsArePending() async throws {
        // Arrange
        let containerA = try makeTestContainer()
        let contextA = containerA.mainContext
        _ = try seed(into: contextA)
        let serviceA = makeService(context: contextA, documentsDirectory: try tempDirectory())
        let url = try await serviceA.exportBackup()

        let containerB = try makeTestContainer()
        let contextB = containerB.mainContext
        let serviceB = makeService(context: contextB, documentsDirectory: try tempDirectory())

        // Act
        _ = try await serviceB.importBackup(from: url)

        // Assert — per-record status
        let workout = try #require(try await SwiftDataWorkoutRepository(context: contextB).fetchAll().first)
        #expect(workout.syncStatus == .pending)
        let template = try #require(try await SwiftDataTemplateRepository(context: contextB).fetchAll().first)
        #expect(template.syncStatus == .pending)
        let pref = try #require(try await SwiftDataTrainingPreferenceRepository(context: contextB).fetchAll().first)
        #expect(pref.syncStatus == .pending)

        // Assert — synced types surface via fetchPending() (the snapshot-push
        // trigger). Preferences no longer sync, so their .pending flag above is
        // informational only.
        let pendingWorkouts = try await SwiftDataWorkoutRepository(context: contextB).fetchPending().count
        #expect(pendingWorkouts == 1)
        let pendingTemplates = try await SwiftDataTemplateRepository(context: contextB).fetchPending().count
        #expect(pendingTemplates == 1)
    }

    @Test("Import aborts before any write when an exercise reference is unresolvable")
    func importAbortsOnUnresolvableExercise() async throws {
        // Arrange — a backup whose workout references an exercise that is
        // neither in the destination store nor in the backup's own exercises.
        let containerA = try makeTestContainer()
        let contextA = containerA.mainContext
        let ghost = Exercise(name: "Ghost Machine", isCustom: false)  // bundled → not exported
        contextA.insert(ghost)
        let workout = Workout(name: "Orphan Day", startedAt: .now)
        contextA.insert(workout)
        let we = WorkoutExercise(order: 0, exercise: ghost)
        contextA.insert(we)
        workout.exercises.append(we)
        let pref = TrainingPreference(key: "orphan_pref", value: "x", source: nil)
        contextA.insert(pref)
        try contextA.save()
        let serviceA = makeService(context: contextA, documentsDirectory: try tempDirectory())
        let url = try await serviceA.exportBackup()

        let containerB = try makeTestContainer()
        let contextB = containerB.mainContext
        let serviceB = makeService(context: contextB, documentsDirectory: try tempDirectory())

        // Act + Assert — the preflight must throw, and NOTHING may be written
        // (a partially imported parent could never be repaired by re-import).
        await #expect(throws: BackupError.self) {
            _ = try await serviceB.importBackup(from: url)
        }
        let workouts = try await SwiftDataWorkoutRepository(context: contextB).fetchAll()
        #expect(workouts.isEmpty)
        let prefs = try await SwiftDataTrainingPreferenceRepository(context: contextB).fetchAll()
        #expect(prefs.isEmpty)
    }

    @Test("Import merges preferences by key, not only by id")
    func importMergesPreferencesByKey() async throws {
        // Arrange — destination already has the same preference KEY under a
        // different UUID (the app upserts preferences by key operationally).
        let containerA = try makeTestContainer()
        let contextA = containerA.mainContext
        let ids = try seed(into: contextA)
        let serviceA = makeService(context: contextA, documentsDirectory: try tempDirectory())
        let url = try await serviceA.exportBackup()

        let containerB = try makeTestContainer()
        let contextB = containerB.mainContext
        let existing = TrainingPreference(key: ids.preferenceKey, value: "strength", source: "user_stated")
        contextB.insert(existing)
        try contextB.save()
        let serviceB = makeService(context: contextB, documentsDirectory: try tempDirectory())

        // Act
        let summary = try await serviceB.importBackup(from: url)

        // Assert — skipped by key; no duplicate-key second record inserted.
        #expect(summary.preferences.imported == 0)
        #expect(summary.preferences.skipped == 1)
        let all = try await SwiftDataTrainingPreferenceRepository(context: contextB).fetchAll()
        #expect(all.filter { $0.key == ids.preferenceKey }.count == 1)
        #expect(all.first { $0.key == ids.preferenceKey }?.value == "strength")
    }

    // MARK: - Bundled-exercise user data (#140)
    //
    // Notes written on a bundled exercise — machine settings, per #136 — are
    // the one thing a bundled exercise carries that the app bundle cannot
    // restore. Excluding them from backup meant a reinstall silently lost
    // "Ankle 4; Seat 4; Pivot 1" with no way to get it back.
    //
    // Carried as an overlay keyed by `externalId`, never by `id`: a fresh
    // store re-imports the catalog with brand-new random UUIDs, so a
    // UUID-keyed overlay would attach to nothing.

    @Test("Export carries notes on bundled exercises as an externalId-keyed overlay")
    func exportCarriesBundledExerciseOverlay() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        try seed(into: context)
        let bundled = Exercise(
            name: "Seated Leg Curl",
            isCustom: false,
            externalId: "Seated_Leg_Curl",
            notes: "Ankle 4; Seat 4; Pivot 1"
        )
        context.insert(bundled)
        // A bundled exercise with no user data must not bloat the file.
        context.insert(Exercise(name: "Plain", isCustom: false, externalId: "Plain"))
        try context.save()

        let dir = try tempDirectory()
        let service = makeService(context: context, documentsDirectory: dir)
        let url = try await service.exportBackup()

        let document = try JSONDecoder().decode(
            BackupDocument.self,
            from: try Data(contentsOf: url)
        )
        #expect(document.formatVersion == 2)
        #expect(document.exerciseOverlays.count == 1)
        let overlay = try #require(document.exerciseOverlays.first)
        #expect(overlay.externalId == "Seated_Leg_Curl")
        #expect(overlay.notes == "Ankle 4; Seat 4; Pivot 1")
        // Custom exercises travel in full and must not be duplicated here.
        #expect(document.exerciseOverlays.allSatisfy { $0.externalId != nil })
        withExtendedLifetime(container) {}
    }

    @Test("Import re-attaches an overlay by externalId even though the UUID differs")
    func importReattachesOverlayByExternalId() async throws {
        // Export from one store…
        let source = try makeTestContainer()
        let sourceContext = source.mainContext
        try seed(into: sourceContext)
        let bundled = Exercise(
            name: "Seated Leg Curl",
            isCustom: false,
            externalId: "Seated_Leg_Curl",
            notes: "Ankle 4; Seat 4; Pivot 1"
        )
        sourceContext.insert(bundled)
        try sourceContext.save()
        let dir = try tempDirectory()
        let url = try await makeService(context: sourceContext, documentsDirectory: dir)
            .exportBackup()

        // …into a fresh store where the catalog has been re-imported with a
        // different UUID for the same exercise. This is the reinstall case.
        let destination = try makeTestContainer()
        let destContext = destination.mainContext
        let reimported = Exercise(
            name: "Seated Leg Curl",
            isCustom: false,
            externalId: "Seated_Leg_Curl"
        )
        destContext.insert(reimported)
        try destContext.save()
        #expect(reimported.id != bundled.id, "a re-import mints a new UUID")

        let summary = try await makeService(context: destContext, documentsDirectory: dir)
            .importBackup(from: url)

        #expect(reimported.notes == "Ankle 4; Seat 4; Pivot 1")
        #expect(summary.exerciseOverlays.imported == 1)
        withExtendedLifetime(source) {}
        withExtendedLifetime(destination) {}
    }

    @Test("An overlay for an exercise that is not present is skipped, not invented")
    func importSkipsOverlayWithNoMatchingExercise() async throws {
        let source = try makeTestContainer()
        let sourceContext = source.mainContext
        try seed(into: sourceContext)
        sourceContext.insert(Exercise(
            name: "Obscure Machine",
            isCustom: false,
            externalId: "Obscure_Machine",
            notes: "Seat 2"
        ))
        try sourceContext.save()
        let dir = try tempDirectory()
        let url = try await makeService(context: sourceContext, documentsDirectory: dir)
            .exportBackup()

        let destination = try makeTestContainer()
        let destContext = destination.mainContext
        let summary = try await makeService(context: destContext, documentsDirectory: dir)
            .importBackup(from: url)

        #expect(summary.exerciseOverlays.imported == 0)
        #expect(summary.exerciseOverlays.skipped == 1)
        withExtendedLifetime(source) {}
        withExtendedLifetime(destination) {}
    }

    @Test("A v1 backup written before overlays existed still imports")
    func importAcceptsV1BackupWithoutOverlays() async throws {
        let dir = try tempDirectory()
        let legacy = """
        {
          "formatVersion": 1,
          "exportedAt": 776000000,
          "workouts": [],
          "templates": [],
          "customExercises": [],
          "preferences": []
        }
        """
        let url = dir.appending(path: "legacy.json")
        try Data(legacy.utf8).write(to: url)

        let container = try makeTestContainer()
        let summary = try await makeService(
            context: container.mainContext,
            documentsDirectory: dir
        ).importBackup(from: url)

        #expect(summary.exerciseOverlays == BackupImportSummary.CollectionResult())
        withExtendedLifetime(container) {}
    }
}
