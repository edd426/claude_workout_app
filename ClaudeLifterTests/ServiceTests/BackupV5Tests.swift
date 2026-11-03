import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// Backup export/import for the V5 data: body measurements, medications and
/// doses, template-exercise alternatives, and height. Import merges by id and
/// never overwrites, like every other collection.
@Suite("BackupService — V5 data")
@MainActor
struct BackupV5Tests {

    /// Retains the container (iOS 26.5 traps when a context outlives it).
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
        let settings: SettingsManager
        let service: BackupService
        let measurements: SwiftDataBodyMeasurementRepository
        let medications: SwiftDataMedicationRepository
        let doses: SwiftDataMedicationDoseRepository
        let alternatives: SwiftDataExerciseAlternativeRepository
    }

    private func makeStore(documents: URL) throws -> Store {
        let container = try makeTestContainer()
        let context = container.mainContext
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "backup-v5-\(UUID())")!)
        let measurements = SwiftDataBodyMeasurementRepository(context: context)
        let medications = SwiftDataMedicationRepository(context: context)
        let doses = SwiftDataMedicationDoseRepository(context: context)
        let alternatives = SwiftDataExerciseAlternativeRepository(context: context)
        let service = BackupService(
            modelContext: context,
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            bodyMeasurementRepository: measurements,
            medicationRepository: medications,
            medicationDoseRepository: doses,
            exerciseAlternativeRepository: alternatives,
            settings: settings,
            documentsDirectory: documents
        )
        return Store(
            container: container, context: context, settings: settings, service: service,
            measurements: measurements, medications: medications, doses: doses, alternatives: alternatives
        )
    }

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "backup-v5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private struct Seeded {
        let medicationId: UUID
        let doseId: UUID
        let templateExerciseId: UUID
    }

    /// A template on a CUSTOM exercise (so it resolves in a fresh store), an
    /// alternative on its one slot, a waist measurement, a vial medication
    /// with one dose, and a height.
    @discardableResult
    private func seed(_ store: Store) async throws -> Seeded {
        let custom = Exercise(name: "Belt Squat", isCustom: true)
        store.context.insert(custom)
        let template = WorkoutTemplate(name: "Mon Legs 1")
        let te = TemplateExercise(order: 0, exercise: custom, defaultSets: 3, defaultReps: 8)
        template.exercises.append(te)
        try await SwiftDataTemplateRepository(context: store.context).save(template)
        try await store.alternatives.replaceAlternatives(
            forTemplateExercise: te.id, with: [AlternativeSpec(externalId: "Leg_Press", note: "if the belt squat is taken")]
        )

        try await store.measurements.save(BodyMeasurement(site: .waist, valueCm: 86.5, note: "navel"))
        let medication = Medication(name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2, allowsSyringeUnits: true)
        try await store.medications.save(medication)
        let dose = MedicationDose(logging: 50, unit: .syringeUnits, of: medication)
        try await store.doses.save(dose)
        store.settings.heightCm = 182.88
        return Seeded(medicationId: medication.id, doseId: dose.id, templateExerciseId: te.id)
    }

    @Test("Export carries measurements, medications, doses, alternatives and height")
    func exportCarriesV5() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try makeStore(documents: dir)
        let seeded = try await seed(store)

        let url = try await store.service.exportBackup()
        let document = try JSONDecoder().decode(BackupDocument.self, from: Data(contentsOf: url))

        #expect(document.bodyMeasurements.map(\.valueCm) == [86.5])
        #expect(document.medications.map(\.id) == [seeded.medicationId])
        #expect(document.medicationDoses.map(\.id) == [seeded.doseId])
        #expect(document.medicationDoses.first?.medicationId == seeded.medicationId)
        #expect(document.exerciseAlternatives.map(\.templateExerciseId) == [seeded.templateExerciseId])
        #expect(document.heightCm == 182.88)
    }

    @Test("Round-trip export then import into a fresh store restores the V5 data exactly")
    func roundTrip() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeStore(documents: dir)
        let seeded = try await seed(source)
        let url = try await source.service.exportBackup()

        let destination = try makeStore(documents: dir)
        let summary = try await destination.service.importBackup(from: url)

        #expect(summary.bodyMeasurements.imported == 1)
        #expect(summary.medications.imported == 1)
        #expect(summary.medicationDoses.imported == 1)
        #expect(summary.exerciseAlternatives.imported == 1)
        #expect(summary.heightImported)

        #expect(try await destination.measurements.fetchAll().first?.note == "navel")
        let medication = try #require(try await destination.medications.fetch(id: seeded.medicationId))
        #expect(medication.effectiveConcentrationMgPerMl == 5)
        let dose = try #require(try await destination.doses.fetch(for: medication).first)
        #expect(dose.id == seeded.doseId)
        #expect(dose.computedMg == 2.5)
        #expect(dose.concentrationMgPerMlAtLog == 5)
        let alternatives = try await destination.alternatives.alternatives(forTemplateExercise: seeded.templateExerciseId)
        #expect(alternatives.map(\.externalId) == ["Leg_Press"])
        #expect(alternatives.first?.note == "if the belt squat is taken")
        #expect(destination.settings.heightCm == 182.88)
    }

    @Test("A tablet dose's snapshotted strength survives a backup round-trip")
    func tabletStrengthRoundTrips() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeStore(documents: dir)
        let medication = Medication(name: "Tabs", doseForm: .tablet, tabletStrengthMg: 50)
        try await source.medications.save(medication)
        let dose = MedicationDose(logging: 1.5, unit: .tablet, of: medication)
        try await source.doses.save(dose)
        // The prescription changed after the dose was logged.
        medication.tabletStrengthMg = 25
        try await source.medications.update(medication)
        let url = try await source.service.exportBackup()

        let destination = try makeStore(documents: dir)
        _ = try await destination.service.importBackup(from: url)

        let restored = try #require(try await destination.doses.fetch(id: dose.id))
        #expect(restored.tabletStrengthMgAtLog == 50)
        #expect(restored.computedMg == 75)
        #expect(restored.medication?.tabletStrengthMg == 25)
    }

    /// #170: an MCP-attached photo on a BUNDLED exercise lives only in the
    /// #140 overlay, keyed by externalId — a reinstall re-imports the catalog
    /// with fresh UUIDs, and the photo must still find its exercise.
    @Test("A bundled exercise's blob photo round-trips through backup as an overlay")
    func overlayPhotoRoundTrips() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeStore(documents: dir)
        let original = Exercise(name: "Leg Extensions", isCustom: false, externalId: "Leg_Extensions")
        original.photoURL = "exercises/ext/Leg_Extensions.jpg"
        source.context.insert(original)
        try source.context.save()
        let url = try await source.service.exportBackup()

        let destination = try makeStore(documents: dir)
        let reimported = Exercise(name: "Leg Extensions", isCustom: false, externalId: "Leg_Extensions")
        destination.context.insert(reimported)
        try destination.context.save()
        let summary = try await destination.service.importBackup(from: url)

        #expect(reimported.id != original.id)
        #expect(summary.exerciseOverlays.imported == 1)
        #expect(reimported.photoURL == "exercises/ext/Leg_Extensions.jpg")
    }

    @Test("Importing the same backup twice skips every existing V5 record")
    func importTwiceSkips() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeStore(documents: dir)
        try await seed(source)
        let url = try await source.service.exportBackup()
        let destination = try makeStore(documents: dir)
        _ = try await destination.service.importBackup(from: url)

        let second = try await destination.service.importBackup(from: url)

        #expect(second.bodyMeasurements.skipped == 1)
        #expect(second.medications.skipped == 1)
        #expect(second.medicationDoses.skipped == 1)
        #expect(second.exerciseAlternatives.skipped == 1)
        #expect(try await destination.measurements.fetchAll().count == 1)
        #expect(try await destination.doses.fetchAll().count == 1)
        #expect(try await destination.alternatives.fetchAll().count == 1)
    }

    @Test("Import never overwrites a height already set on this phone")
    func importKeepsExistingHeight() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeStore(documents: dir)
        try await seed(source)
        let url = try await source.service.exportBackup()
        let destination = try makeStore(documents: dir)
        destination.settings.heightCm = 170

        let summary = try await destination.service.importBackup(from: url)

        #expect(destination.settings.heightCm == 170)
        #expect(!summary.heightImported)
    }

    @Test("Imported V5 records are pending so they push")
    func importedArePending() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeStore(documents: dir)
        try await seed(source)
        let url = try await source.service.exportBackup()
        let destination = try makeStore(documents: dir)

        _ = try await destination.service.importBackup(from: url)

        #expect(try await destination.measurements.fetchPending().count == 1)
        #expect(try await destination.medications.fetchPending().count == 1)
        #expect(try await destination.doses.fetchPending().count == 1)
        #expect(try await destination.alternatives.fetchPending().count == 1)
    }

    @Test("A dose whose medication is in neither the backup nor this phone is skipped, not orphaned")
    func orphanDoseSkipped() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stamp = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let document = BackupDocument(
            formatVersion: 3, exportedAt: stamp, workouts: [], templates: [], customExercises: [], preferences: [],
            medicationDoses: [MedicationDoseDTO(
                id: UUID(), medicationId: UUID(), takenAt: stamp, amount: 1, unit: "tablet",
                computedMg: 50, concentrationMgPerMlAtLog: nil, note: nil, lastModified: stamp
            )]
        )
        let url = dir.appending(path: "orphan.json")
        try JSONEncoder().encode(document).write(to: url)
        let store = try makeStore(documents: dir)

        let summary = try await store.service.importBackup(from: url)

        #expect(summary.medicationDoses.skipped == 1)
        #expect(try await store.doses.fetchAll().isEmpty)
    }

    @Test("A backup written before V5 still imports, with nothing V5 in it")
    func preV5BackupImports() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        {
          "formatVersion": 2, "exportedAt": 800000000,
          "workouts": [], "templates": [], "customExercises": [], "preferences": [],
          "exerciseOverlays": []
        }
        """
        let url = dir.appending(path: "v2.json")
        try Data(json.utf8).write(to: url)
        let store = try makeStore(documents: dir)
        store.settings.heightCm = 182.88

        let summary = try await store.service.importBackup(from: url)

        #expect(summary.medications.imported == 0)
        #expect(!summary.heightImported)
        #expect(store.settings.heightCm == 182.88)
    }
}
