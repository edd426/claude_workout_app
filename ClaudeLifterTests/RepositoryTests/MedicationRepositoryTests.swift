import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("MedicationRepository Tests")
@MainActor
struct MedicationRepositoryTests {

    private struct Setup {
        let container: ModelContainer
        let medications: SwiftDataMedicationRepository
        let doses: SwiftDataMedicationDoseRepository
    }

    private func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        let context = container.mainContext
        return Setup(
            container: container,
            medications: SwiftDataMedicationRepository(context: context),
            doses: SwiftDataMedicationDoseRepository(context: context)
        )
    }

    @Test("Added medications list by name, archived included in all")
    func fetchAllByName() async throws {
        let setup = try makeSetup()
        try await setup.medications.save(Medication(name: "Zeta", doseForm: .tablet, tabletStrengthMg: 50))
        try await setup.medications.save(Medication(name: "Alpha", doseForm: .mass, massUnit: .mg, isArchived: true))

        let all = try await setup.medications.fetchAll()
        #expect(all.map(\.name) == ["Alpha", "Zeta"])
    }

    @Test("An archived medication drops out of the active (quick-log) list")
    func archivedLeavesActiveList() async throws {
        let setup = try makeSetup()
        let kept = Medication(name: "Kept", doseForm: .mass, massUnit: .mg)
        let retired = Medication(name: "Retired", doseForm: .mass, massUnit: .mg)
        try await setup.medications.save(kept)
        try await setup.medications.save(retired)

        try await setup.medications.archive(retired)

        #expect(try await setup.medications.fetchActive().map(\.name) == ["Kept"])
        #expect(try await setup.medications.fetchAll().count == 2)
        #expect(retired.isArchived)
    }

    @Test("An archived medication keeps its dose history")
    func archiveKeepsHistory() async throws {
        let setup = try makeSetup()
        let medication = Medication(name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2)
        try await setup.medications.save(medication)
        try await setup.doses.save(MedicationDose(logging: 0.5, unit: .mL, of: medication))
        try await setup.doses.save(MedicationDose(logging: 0.4, unit: .mL, of: medication))

        try await setup.medications.archive(medication)

        let history = try await setup.doses.fetch(for: medication)
        #expect(history.count == 2)
        #expect(medication.doses.count == 2)
    }

    @Test("Unarchiving brings a medication back to the active list")
    func unarchive() async throws {
        let setup = try makeSetup()
        let medication = Medication(name: "Back", doseForm: .units, isArchived: true)
        try await setup.medications.save(medication)

        try await setup.medications.unarchive(medication)

        #expect(try await setup.medications.fetchActive().map(\.name) == ["Back"])
    }

    @Test("Archive and update mark the medication changed so it pushes")
    func archiveAndUpdateRecordChange() async throws {
        let setup = try makeSetup()
        let old = Date(timeIntervalSince1970: 1_000)
        let medication = Medication(name: "Vial A", doseForm: .liquid, syncStatus: .synced, lastModified: old)
        try await setup.medications.save(medication)

        medication.setVialMix(amountMg: 10, diluentMl: 2)
        try await setup.medications.update(medication)
        #expect(medication.syncStatus == .pending)
        #expect(medication.lastModified > old)

        medication.syncStatus = .synced
        try await setup.medications.archive(medication)
        #expect(medication.syncStatus == .pending)
    }

    @Test("Fetch by id finds the medication, and nil for an unknown id")
    func fetchById() async throws {
        let setup = try makeSetup()
        let medication = Medication(name: "Find me", doseForm: .mass, massUnit: .mcg)
        try await setup.medications.save(medication)

        #expect(try await setup.medications.fetch(id: medication.id)?.name == "Find me")
        #expect(try await setup.medications.fetch(id: UUID()) == nil)
    }

    @Test("Pending lists only medications not yet pushed")
    func fetchPending() async throws {
        let setup = try makeSetup()
        try await setup.medications.save(Medication(name: "New", doseForm: .units))
        try await setup.medications.save(Medication(name: "Old", doseForm: .units, syncStatus: .synced))

        #expect(try await setup.medications.fetchPending().map(\.name) == ["New"])
    }

    @Test("Deleting a medication (restore only) takes its doses with it")
    func deleteCascadesToDoses() async throws {
        let setup = try makeSetup()
        let medication = Medication(name: "Gone", doseForm: .tablet, tabletStrengthMg: 10)
        try await setup.medications.save(medication)
        try await setup.doses.save(MedicationDose(logging: 1, unit: .tablet, of: medication))

        try await setup.medications.delete(medication)

        #expect(try await setup.medications.fetchAll().isEmpty)
        #expect(try await setup.doses.fetchAll().isEmpty)
    }
}
