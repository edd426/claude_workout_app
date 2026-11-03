import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// Wire format for the schemaVersion 5 snapshot: body measurements (#165),
/// medications and doses (#164), template-exercise alternatives, and height.
@Suite("SyncMapper + DTO — snapshot v5")
@MainActor
struct SyncV5MapperTests {

    private let encoder = NetworkService.makeWireEncoder()
    private let decoder = NetworkService.makeWireDecoder()
    private let stamp = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Body measurements

    @Test("BodyMeasurement maps to its DTO with the site as a raw string")
    func measurementToDTO() {
        let measurement = BodyMeasurement(site: .waist, valueCm: 86.5, recordedAt: stamp, note: "navel", lastModified: stamp)
        let dto = SyncMapper.toDTO(measurement)
        #expect(dto.id == measurement.id)
        #expect(dto.site == "waist")
        #expect(dto.valueCm == 86.5)
        #expect(dto.recordedAt == stamp)
        #expect(dto.note == "navel")
        #expect(dto.lastModified == stamp)
    }

    @Test("A restored measurement is synced and keeps an unknown site verbatim")
    func createMeasurementFromDTO() {
        let dto = BodyMeasurementDTO(id: UUID(), site: "neck", valueCm: 39, recordedAt: stamp, note: nil, lastModified: stamp)
        let measurement = SyncMapper.createBodyMeasurement(from: dto)
        #expect(measurement.id == dto.id)
        #expect(measurement.siteRaw == "neck")
        #expect(measurement.site == nil)
        #expect(measurement.syncStatus == .synced)
        #expect(measurement.lastModified == stamp)
    }

    // MARK: - Medications

    @Test("Medication maps every stored field to its DTO")
    func medicationToDTO() {
        let medication = Medication(
            name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2,
            allowsSyringeUnits: true, isArchived: true, createdAt: stamp, lastModified: stamp
        )
        let dto = SyncMapper.toDTO(medication)
        #expect(dto.id == medication.id)
        #expect(dto.name == "Vial A")
        #expect(dto.doseForm == "liquid")
        #expect(dto.massUnit == nil)
        #expect(dto.vialAmountMg == 10)
        #expect(dto.diluentMl == 2)
        #expect(dto.concentrationMgPerMl == nil)
        #expect(dto.allowsSyringeUnits)
        #expect(dto.isArchived)
        #expect(dto.createdAt == stamp)
    }

    @Test("A restored medication is synced and keeps its raw dose form")
    func createMedicationFromDTO() {
        let dto = MedicationDTO(
            id: UUID(), name: "Patch", doseForm: "patch", massUnit: "mcg", tabletStrengthMg: nil,
            concentrationMgPerMl: nil, vialAmountMg: nil, diluentMl: nil,
            allowsSyringeUnits: false, isArchived: false, createdAt: stamp, lastModified: stamp
        )
        let medication = SyncMapper.createMedication(from: dto)
        #expect(medication.id == dto.id)
        #expect(medication.doseFormRaw == "patch")
        #expect(medication.massUnitRaw == "mcg")
        #expect(medication.syncStatus == .synced)
    }

    // MARK: - Doses

    @Test("A dose maps to its DTO carrying its medication's id and the logged snapshot")
    func doseToDTO() {
        let medication = Medication(name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2)
        let dose = MedicationDose(logging: 50, unit: .syringeUnits, of: medication, takenAt: stamp, note: "left side")
        let dto = SyncMapper.toDTO(dose)
        #expect(dto.id == dose.id)
        #expect(dto.medicationId == medication.id)
        #expect(dto.takenAt == stamp)
        #expect(dto.amount == 50)
        #expect(dto.unit == "syringeUnits")
        #expect(dto.computedMg == 2.5)
        #expect(dto.concentrationMgPerMlAtLog == 5)
        #expect(dto.note == "left side")
    }

    @Test("A restored dose keeps its stored mg rather than recomputing it")
    func createDoseFromDTO() throws {
        let container = try makeTestContainer()
        let medication = Medication(name: "Vial B", doseForm: .liquid, concentrationMgPerMl: 10)
        container.mainContext.insert(medication)
        let dto = MedicationDoseDTO(
            id: UUID(), medicationId: medication.id, takenAt: stamp, amount: 0.5, unit: "mL",
            computedMg: 2.5, concentrationMgPerMlAtLog: 5, note: nil, lastModified: stamp
        )

        let dose = SyncMapper.createMedicationDose(from: dto, medication: medication)

        #expect(dose.id == dto.id)
        #expect(dose.medication?.id == medication.id)
        #expect(dose.computedMg == 2.5)  // not 0.5 × today's 10 mg/mL
        #expect(dose.concentrationMgPerMlAtLog == 5)
        #expect(dose.syncStatus == .synced)
    }

    // MARK: - Alternatives

    @Test("An alternative maps to its DTO and back")
    func alternativeRoundTrip() {
        let teId = UUID()
        let alternative = ExerciseAlternative(templateExerciseId: teId, externalId: "Leg_Press", order: 1, note: "if the rack is taken", lastModified: stamp)
        let dto = SyncMapper.toDTO(alternative)
        #expect(dto.templateExerciseId == teId)
        #expect(dto.externalId == "Leg_Press")
        #expect(dto.order == 1)
        #expect(dto.note == "if the rack is taken")

        let restored = SyncMapper.createExerciseAlternative(from: dto)
        #expect(restored.id == alternative.id)
        #expect(restored.templateExerciseId == teId)
        #expect(restored.syncStatus == .synced)
    }

    // MARK: - Snapshot wire contract v5

    @Test("A v5 push encodes every new collection and heightCm, null when unset")
    func pushEncodesV5Keys() throws {
        let request = SnapshotPushRequest(
            snapshot: SyncSnapshot(workouts: [], templates: [], customExercises: [], bodyWeightEntries: [])
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]
        )
        #expect(json["schemaVersion"] as? Int == 5)
        let snapshot = try #require(json["snapshot"] as? [String: Any])
        #expect(snapshot["bodyMeasurements"] as? [Any] != nil)
        #expect(snapshot["medications"] as? [Any] != nil)
        #expect(snapshot["medicationDoses"] as? [Any] != nil)
        #expect(snapshot["exerciseAlternatives"] as? [Any] != nil)
        // Present and null: "no height" is a value the server must store, not
        // a missing key it may skip.
        #expect(snapshot.keys.contains("heightCm"))
        #expect(snapshot["heightCm"] is NSNull)
    }

    @Test("heightCm encodes as a number when set")
    func heightEncodesAsNumber() throws {
        let snapshot = SyncSnapshot(
            workouts: [], templates: [], customExercises: [], bodyWeightEntries: [], heightCm: 182.88
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any]
        )
        #expect(json["heightCm"] as? Double == 182.88)
    }

    @Test("A v4 mirror without the v5 keys decodes, and says it does not carry them")
    func v4SnapshotDecodes() throws {
        let json = """
        {
          "workouts": [], "templates": [], "customExercises": [],
          "bodyWeightEntries": [], "exerciseReports": [], "exerciseOverlays": []
        }
        """
        let snapshot = try decoder.decode(SyncSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.bodyMeasurements.isEmpty)
        #expect(snapshot.medications.isEmpty)
        #expect(snapshot.medicationDoses.isEmpty)
        #expect(snapshot.exerciseAlternatives.isEmpty)
        #expect(snapshot.heightCm == nil)
        #expect(!snapshot.carriesV5Collections)
    }

    @Test("A v5 mirror round-trips its collections and height")
    func v5SnapshotRoundTrips() throws {
        let medicationId = UUID()
        let snapshot = SyncSnapshot(
            workouts: [], templates: [], customExercises: [], bodyWeightEntries: [],
            bodyMeasurements: [BodyMeasurementDTO(id: UUID(), site: "waist", valueCm: 86.5, recordedAt: stamp, note: nil, lastModified: stamp)],
            medications: [MedicationDTO(
                id: medicationId, name: "Vial A", doseForm: "liquid", massUnit: nil, tabletStrengthMg: nil,
                concentrationMgPerMl: nil, vialAmountMg: 10, diluentMl: 2,
                allowsSyringeUnits: true, isArchived: false, createdAt: stamp, lastModified: stamp
            )],
            medicationDoses: [MedicationDoseDTO(
                id: UUID(), medicationId: medicationId, takenAt: stamp, amount: 50, unit: "syringeUnits",
                computedMg: 2.5, concentrationMgPerMlAtLog: 5, note: nil, lastModified: stamp
            )],
            exerciseAlternatives: [ExerciseAlternativeDTO(
                id: UUID(), templateExerciseId: UUID(), externalId: "Leg_Press", order: 0, note: nil, lastModified: stamp
            )],
            heightCm: 182.88
        )

        let decoded = try decoder.decode(SyncSnapshot.self, from: encoder.encode(snapshot))

        #expect(decoded.carriesV5Collections)
        #expect(decoded.heightCm == 182.88)
        #expect(decoded.bodyMeasurements.first?.valueCm == 86.5)
        #expect(decoded.medications.first?.vialAmountMg == 10)
        #expect(decoded.medicationDoses.first?.medicationId == medicationId)
        #expect(decoded.medicationDoses.first?.computedMg == 2.5)
        #expect(decoded.exerciseAlternatives.first?.externalId == "Leg_Press")
    }
}
