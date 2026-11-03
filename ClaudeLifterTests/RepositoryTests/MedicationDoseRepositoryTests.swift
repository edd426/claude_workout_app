import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("MedicationDoseRepository Tests")
@MainActor
struct MedicationDoseRepositoryTests {

    @MainActor
    final class DeletionCounter {
        var count = 0
    }

    private struct Setup {
        let container: ModelContainer
        let medications: SwiftDataMedicationRepository
        let doses: SwiftDataMedicationDoseRepository
        let deletions: DeletionCounter
    }

    private func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        let context = container.mainContext
        let counter = DeletionCounter()
        return Setup(
            container: container,
            medications: SwiftDataMedicationRepository(context: context),
            doses: SwiftDataMedicationDoseRepository(context: context, onDeletion: { counter.count += 1 }),
            deletions: counter
        )
    }

    private let day: TimeInterval = 86_400

    @Test("Doses list per medication, newest-first, and never another medication's")
    func fetchForMedication() async throws {
        let setup = try makeSetup()
        let a = Medication(name: "A", doseForm: .mass, massUnit: .mg)
        let b = Medication(name: "B", doseForm: .mass, massUnit: .mg)
        try await setup.medications.save(a)
        try await setup.medications.save(b)
        try await setup.doses.save(MedicationDose(logging: 5, unit: .mg, of: a, takenAt: Date(timeIntervalSinceNow: -day)))
        try await setup.doses.save(MedicationDose(logging: 10, unit: .mg, of: a, takenAt: .now))
        try await setup.doses.save(MedicationDose(logging: 99, unit: .mg, of: b, takenAt: .now))

        let history = try await setup.doses.fetch(for: a)
        #expect(history.map(\.amount) == [10, 5])
    }

    @Test("Doses list per medication within a date range, oldest-first for charts")
    func fetchForMedicationInRange() async throws {
        let setup = try makeSetup()
        let now = Date()
        let a = Medication(name: "A", doseForm: .mass, massUnit: .mg)
        let b = Medication(name: "B", doseForm: .mass, massUnit: .mg)
        try await setup.medications.save(a)
        try await setup.medications.save(b)
        try await setup.doses.save(MedicationDose(logging: 1, unit: .mg, of: a, takenAt: now.addingTimeInterval(-40 * day)))
        try await setup.doses.save(MedicationDose(logging: 2, unit: .mg, of: a, takenAt: now.addingTimeInterval(-10 * day)))
        try await setup.doses.save(MedicationDose(logging: 3, unit: .mg, of: a, takenAt: now.addingTimeInterval(-1 * day)))
        try await setup.doses.save(MedicationDose(logging: 9, unit: .mg, of: b, takenAt: now.addingTimeInterval(-5 * day)))

        let window = try await setup.doses.fetch(for: a, from: now.addingTimeInterval(-30 * day), to: now)
        #expect(window.map(\.amount) == [2, 3])
    }

    @Test("A date range across all medications, oldest-first")
    func fetchRangeAcrossMedications() async throws {
        let setup = try makeSetup()
        let now = Date()
        let a = Medication(name: "A", doseForm: .mass, massUnit: .mg)
        let b = Medication(name: "B", doseForm: .units)
        try await setup.medications.save(a)
        try await setup.medications.save(b)
        try await setup.doses.save(MedicationDose(logging: 1, unit: .mg, of: a, takenAt: now.addingTimeInterval(-3 * day)))
        try await setup.doses.save(MedicationDose(logging: 2000, unit: .IU, of: b, takenAt: now.addingTimeInterval(-2 * day)))
        try await setup.doses.save(MedicationDose(logging: 7, unit: .mg, of: a, takenAt: now.addingTimeInterval(-60 * day)))

        let window = try await setup.doses.fetchRange(from: now.addingTimeInterval(-7 * day), to: now)
        #expect(window.map(\.amount) == [1, 2000])
    }

    @Test("Latest dose for a medication backs \"log the same as last time\"")
    func fetchLatestForMedication() async throws {
        let setup = try makeSetup()
        let a = Medication(name: "A", doseForm: .tablet, tabletStrengthMg: 50)
        let b = Medication(name: "B", doseForm: .tablet, tabletStrengthMg: 50)
        try await setup.medications.save(a)
        try await setup.medications.save(b)
        try await setup.doses.save(MedicationDose(logging: 1, unit: .tablet, of: a, takenAt: Date(timeIntervalSinceNow: -day)))
        try await setup.doses.save(MedicationDose(logging: 1.5, unit: .tablet, of: a, takenAt: Date(timeIntervalSinceNow: -60)))
        try await setup.doses.save(MedicationDose(logging: 3, unit: .tablet, of: b, takenAt: .now))

        #expect(try await setup.doses.fetchLatest(for: a)?.amount == 1.5)
        let unused = Medication(name: "C", doseForm: .units)
        try await setup.medications.save(unused)
        #expect(try await setup.doses.fetchLatest(for: unused) == nil)
    }

    @Test("Deleting a dose keeps the medication, drops it from history, and flags a push")
    func deleteDose() async throws {
        let setup = try makeSetup()
        let a = Medication(name: "A", doseForm: .mass, massUnit: .mg)
        try await setup.medications.save(a)
        let keep = MedicationDose(logging: 5, unit: .mg, of: a)
        let drop = MedicationDose(logging: 6, unit: .mg, of: a)
        try await setup.doses.save(keep)
        try await setup.doses.save(drop)

        try await setup.doses.delete(drop)

        #expect(try await setup.doses.fetch(for: a).map(\.amount) == [5])
        #expect(try await setup.medications.fetchAll().count == 1)
        #expect(setup.deletions.count == 1)
    }

    @Test("Updating a revised dose marks it changed so it pushes")
    func updateRecordsChange() async throws {
        let setup = try makeSetup()
        let a = Medication(name: "A", doseForm: .liquid, concentrationMgPerMl: 5)
        try await setup.medications.save(a)
        let dose = MedicationDose(logging: 0.5, unit: .mL, of: a)
        try await setup.doses.save(dose)
        dose.syncStatus = .synced

        dose.revise(amount: 0.6, unit: .mL)
        try await setup.doses.update(dose)

        #expect(dose.syncStatus == .pending)
        #expect(abs((dose.computedMg ?? 0) - 3) < 1e-9)
    }

    @Test("Pending lists only doses not yet pushed")
    func fetchPending() async throws {
        let setup = try makeSetup()
        let a = Medication(name: "A", doseForm: .mass, massUnit: .mg)
        try await setup.medications.save(a)
        try await setup.doses.save(MedicationDose(logging: 5, unit: .mg, of: a))
        let synced = MedicationDose(logging: 6, unit: .mg, of: a)
        synced.syncStatus = .synced
        try await setup.doses.save(synced)

        #expect(try await setup.doses.fetchPending().map(\.amount) == [5])
    }
}
