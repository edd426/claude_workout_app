import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// V3 → V4 (issue #128): template provenance as two new models.
///
/// Worth testing on a **real on-disk store** rather than in memory, because an
/// in-memory container does not exercise migration at all — it would pass while
/// the phone crashed on first launch.
///
/// It caught exactly that. The first attempt put the provenance fields on
/// `Workout` and `WorkoutExercise` and died with `NSInvalidArgumentException:
/// Duplicate version checksums detected`: the `VersionedSchema` model lists
/// name live Swift types, so adding a property changes V1–V3 as well as V4 and
/// all four hash identically. See the note on `ClaudeLifterSchemaV4`.
@Suite("Template Provenance Migration Tests")
@MainActor
struct TemplateProvenanceMigrationTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "provenance-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("A populated V3 store migrates to V4 with every record intact")
    func v3StoreMigratesToV4() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")

        let workoutId = UUID()

        // A genuine V3 store — no migration plan, V3 schema only — populated
        // the way the device actually is: a workout with exercises and sets,
        // a template, and a report.
        do {
            let v3Schema = Schema(versionedSchema: ClaudeLifterSchemaV3.self)
            let container = try ModelContainer(
                for: v3Schema,
                configurations: [ModelConfiguration(schema: v3Schema, url: storeURL)]
            )
            let context = container.mainContext
            let exercise = Exercise(name: "Seated Leg Curl", isCustom: false, externalId: "Seated_Leg_Curl")
            context.insert(exercise)

            let workout = Workout(id: workoutId, name: "Lower B", startedAt: .now)
            context.insert(workout)
            let we = WorkoutExercise(order: 0, exercise: exercise, restSeconds: 90)
            context.insert(we)
            workout.exercises.append(we)
            let set = WorkoutSet(order: 0, weight: 47.5, weightUnit: .kg, reps: 12, isCompleted: true, completedAt: .now)
            context.insert(set)
            we.sets.append(set)

            let template = WorkoutTemplate(name: "Lower B")
            context.insert(template)
            let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 3, defaultReps: 12)
            context.insert(te)
            template.exercises.append(te)

            context.insert(ExerciseReport(category: .bug, detail: "notes missing"))
            try context.save()
        }

        // Reopen through the factory. CurrentSchema is V4, so this runs the
        // V3→V4 stage. `.opened` — a quarantine here is the on-device crash.
        let result = try ModelContainerFactory.make(
            storeURL: storeURL,
            quarantineDirectory: dir.appending(path: "StoreQuarantine")
        )
        #expect(result.outcome == .opened, "a quarantine here means the phone loses its store on first launch")

        let context = result.container.mainContext

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(workouts.count == 1)
        let migrated = try #require(workouts.first)
        #expect(migrated.name == "Lower B")
        #expect(migrated.exercises.count == 1)
        #expect(migrated.exercises.first?.sets.count == 1)
        #expect(migrated.exercises.first?.sets.first?.weight == 47.5)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ExerciseReport>()).count == 1)

        // Pre-existing workouts simply have no baseline. Old history is never
        // retro-reconciled, and its absence must not be an error.
        let baselines = try context.fetch(FetchDescriptor<WorkoutTemplateBaseline>())
        #expect(baselines.isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutExerciseBaseline>()).isEmpty)
        _ = workoutId
    }

    @Test("Provenance is writable and persists in the migrated store")
    func provenanceWritableAfterMigration() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")

        do {
            let v3Schema = Schema(versionedSchema: ClaudeLifterSchemaV3.self)
            let container = try ModelContainer(
                for: v3Schema,
                configurations: [ModelConfiguration(schema: v3Schema, url: storeURL)]
            )
            try container.mainContext.save()
        }

        let result = try ModelContainerFactory.make(
            storeURL: storeURL,
            quarantineDirectory: dir.appending(path: "StoreQuarantine")
        )
        #expect(result.outcome == .opened)
        let context = result.container.mainContext

        let workoutId = UUID()
        let revision = Date(timeIntervalSince1970: 1_787_000_000)
        let baseline = WorkoutTemplateBaseline(
            workoutId: workoutId,
            templateId: UUID(),
            templateRevision: revision,
            templateName: "Lower B"
        )
        context.insert(baseline)
        let entry = WorkoutExerciseBaseline(
            workoutId: workoutId,
            workoutExerciseId: UUID(),
            sourceTemplateExerciseId: UUID(),
            exerciseId: UUID(),
            exerciseExternalId: "Split_Squat_with_Dumbbells",
            exerciseName: "Split Squat with Dumbbells",
            plannedOrder: 1,
            plannedSets: 2,
            plannedReps: 8,
            plannedRestSeconds: 90,
            plannedNotes: "Rear foot on the bench"
        )
        context.insert(entry)
        try context.save()

        let reread = try #require(try context.fetch(FetchDescriptor<WorkoutTemplateBaseline>()).first)
        #expect(reread.templateRevision == revision)
        #expect(reread.templateName == "Lower B")
        let rereadEntry = try #require(try context.fetch(FetchDescriptor<WorkoutExerciseBaseline>()).first)
        #expect(rereadEntry.plannedReps == 8)
        #expect(rereadEntry.plannedSets == 2)
        #expect(rereadEntry.plannedNotes == "Rear foot on the bench")
        #expect(rereadEntry.exerciseExternalId == "Split_Squat_with_Dumbbells")
    }
}
