import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// V4 → V5: body measurements (#165), medications and doses (#164), and
/// template-exercise alternatives. All four are NEW models; no existing model
/// gains a property.
///
/// On a REAL on-disk store, because an in-memory container does not exercise
/// migration at all (see `TemplateProvenanceMigrationTests` for the crash that
/// taught this). A quarantine outcome here is the phone losing its store on
/// the first launch after the update.
@Suite("Schema V5 Migration Tests")
@MainActor
struct SchemaV5MigrationTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "v5-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let v5EntityNames: Set<String> = [
        "BodyMeasurement", "Medication", "MedicationDose", "ExerciseAlternative"
    ]

    /// A genuine V4 store — no migration plan, V4 schema only — populated the
    /// way the phone is: a workout with sets, a template, a weight entry, a
    /// report, and a provenance baseline.
    private func seedV4Store(at storeURL: URL, workoutId: UUID, templateExerciseId: UUID) throws {
        let v4Schema = Schema(versionedSchema: ClaudeLifterSchemaV4.self)
        let container = try ModelContainer(
            for: v4Schema,
            configurations: [ModelConfiguration(schema: v4Schema, url: storeURL)]
        )
        let context = container.mainContext
        let exercise = Exercise(name: "Barbell Squat", isCustom: false, externalId: "Barbell_Squat")
        context.insert(exercise)

        let workout = Workout(id: workoutId, name: "Mon Legs 1", startedAt: .now)
        context.insert(workout)
        let we = WorkoutExercise(order: 0, exercise: exercise, restSeconds: 120)
        context.insert(we)
        workout.exercises.append(we)
        let set = WorkoutSet(order: 0, weight: 100, weightUnit: .kg, reps: 5, isCompleted: true, completedAt: .now)
        context.insert(set)
        we.sets.append(set)

        let template = WorkoutTemplate(name: "Mon Legs 1")
        context.insert(template)
        let te = TemplateExercise(id: templateExerciseId, order: 0, exercise: exercise, defaultSets: 3, defaultReps: 5)
        context.insert(te)
        template.exercises.append(te)

        context.insert(BodyWeightEntry(weightKg: 84.2))
        context.insert(ExerciseReport(category: .swapRequest, detail: "rack always taken"))
        context.insert(WorkoutTemplateBaseline(
            workoutId: workoutId, templateId: template.id, templateName: "Mon Legs 1"
        ))
        try context.save()
    }

    @Test("A populated V4 store opens as V5 with every record intact")
    func v4StoreMigratesToV5() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")
        let workoutId = UUID()
        let templateExerciseId = UUID()
        try seedV4Store(at: storeURL, workoutId: workoutId, templateExerciseId: templateExerciseId)

        let result = try ModelContainerFactory.make(
            storeURL: storeURL,
            quarantineDirectory: dir.appending(path: "StoreQuarantine")
        )
        #expect(result.outcome == .opened, "a quarantine here means the phone loses its store on first launch")

        // The container must actually be V5 before anything touches a V5 type.
        let entityNames = Set(result.container.schema.entities.map(\.name))
        try #require(Self.v5EntityNames.isSubset(of: entityNames), "the opened store is not V5")

        let context = result.container.mainContext
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(workouts.count == 1)
        let migrated = try #require(workouts.first)
        #expect(migrated.id == workoutId)
        #expect(migrated.exercises.first?.sets.first?.weight == 100)
        #expect(migrated.exercises.first?.sets.first?.reps == 5)
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(templates.first?.exercises.first?.id == templateExerciseId)
        #expect(try context.fetch(FetchDescriptor<BodyWeightEntry>()).first?.weightKg == 84.2)
        #expect(try context.fetch(FetchDescriptor<ExerciseReport>()).first?.detail == "rack always taken")
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplateBaseline>()).count == 1)

        // The new collections start empty — nothing is invented by migration.
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Medication>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MedicationDose>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ExerciseAlternative>()).isEmpty)
    }

    @Test("V5 records written to a migrated store survive a reopen")
    func v5RecordsPersistAcrossReopen() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")
        let templateExerciseId = UUID()
        try seedV4Store(at: storeURL, workoutId: UUID(), templateExerciseId: templateExerciseId)
        let quarantine = dir.appending(path: "StoreQuarantine")

        // First open migrates; write one of each new model.
        do {
            let first = try ModelContainerFactory.make(storeURL: storeURL, quarantineDirectory: quarantine)
            #expect(first.outcome == .opened)
            let entityNames = Set(first.container.schema.entities.map(\.name))
            try #require(Self.v5EntityNames.isSubset(of: entityNames), "the opened store is not V5")
            let context = first.container.mainContext

            context.insert(BodyMeasurement(site: .waist, valueCm: 86.5, note: "navel, morning"))
            let medication = Medication(
                name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2, allowsSyringeUnits: true
            )
            context.insert(medication)
            let dose = MedicationDose(logging: 50, unit: .syringeUnits, of: medication)
            context.insert(dose)
            let tablets = Medication(name: "Tabs", doseForm: .tablet, tabletStrengthMg: 50)
            context.insert(tablets)
            context.insert(MedicationDose(logging: 1.5, unit: .tablet, of: tablets))
            context.insert(ExerciseAlternative(
                templateExerciseId: templateExerciseId, externalId: "Leg_Press", order: 0, note: "if the rack is taken"
            ))
            try context.save()
        }

        // Second open: a stable V5 store, no migration, everything still there.
        let second = try ModelContainerFactory.make(storeURL: storeURL, quarantineDirectory: quarantine)
        #expect(second.outcome == .opened)
        let context = second.container.mainContext

        let measurement = try #require(try context.fetch(FetchDescriptor<BodyMeasurement>()).first)
        #expect(measurement.site == .waist)
        #expect(measurement.valueCm == 86.5)
        #expect(measurement.note == "navel, morning")

        let medications = try context.fetch(FetchDescriptor<Medication>())
        let medication = try #require(medications.first { $0.doseForm == .liquid })
        #expect(medication.effectiveConcentrationMgPerMl == 5)
        #expect(medication.doses.count == 1)
        let doses = try context.fetch(FetchDescriptor<MedicationDose>())
        let dose = try #require(doses.first { $0.unit == .syringeUnits })
        #expect(dose.medication?.id == medication.id)
        #expect(dose.computedMg == 2.5)
        #expect(dose.concentrationMgPerMlAtLog == 5)
        let tabletDose = try #require(doses.first { $0.unit == .tablet })
        #expect(tabletDose.tabletStrengthMgAtLog == 50)
        #expect(tabletDose.computedMg == 75)

        let alternative = try #require(try context.fetch(FetchDescriptor<ExerciseAlternative>()).first)
        #expect(alternative.templateExerciseId == templateExerciseId)
        #expect(alternative.externalId == "Leg_Press")
        #expect(alternative.note == "if the rack is taken")
    }
}
