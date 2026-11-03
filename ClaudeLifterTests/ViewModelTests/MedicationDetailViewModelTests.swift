import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("MedicationDetailViewModel")
@MainActor
struct MedicationDetailViewModelTests {
    private struct Setup {
        let container: ModelContainer
        let medication: Medication
        let medications: SwiftDataMedicationRepository
        let doses: SwiftDataMedicationDoseRepository
        let usual: UserDefaultsUsualDoseStore
        let vm: MedicationDetailViewModel
    }

    /// A liquid at 5 mg/mL (10 mg in 2 mL) with three doses over three days.
    private func makeSetup() async throws -> Setup {
        let container = try makeTestContainer()
        let context = container.mainContext
        let medications = SwiftDataMedicationRepository(context: context)
        let doses = SwiftDataMedicationDoseRepository(context: context)
        let usual = UserDefaultsUsualDoseStore(defaults: UserDefaults(suiteName: "usual-\(UUID())")!)
        let medication = Medication(name: "Medication B", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2)
        try await medications.save(medication)
        for (offset, amount) in [(-2, 0.2), (-1, 0.25), (0, 0.3)] {
            try await doses.save(MedicationDose(
                logging: amount, unit: .mL, of: medication,
                takenAt: MedicationTestClock.at(offset, 8, 5)
            ))
        }
        let vm = MedicationDetailViewModel(
            medication: medication,
            medicationRepository: medications,
            doseRepository: doses,
            usualDoses: usual,
            formatter: MedicationTestClock.formatter,
            now: { MedicationTestClock.now }
        )
        await vm.load()
        return Setup(
            container: container, medication: medication, medications: medications,
            doses: doses, usual: usual, vm: vm
        )
    }

    @Test("The history lists every dose, newest first")
    func historyNewestFirst() async throws {
        let setup = try await makeSetup()

        #expect(setup.vm.rows.map(\.amountText) == ["0.3 mL (1.5 mg)", "0.25 mL (1.25 mg)", "0.2 mL (1 mg)"])
        #expect(setup.vm.rows.map(\.whenText) == ["today 8:05", "yesterday 8:05", "Mon 8:05"])
        #expect(setup.vm.strengthText == "5 mg/mL (10 mg in 2 mL)")
        #expect(setup.vm.usualDoseText == "Usual dose 0.3 mL (1.5 mg)")
    }

    @Test("The chart plots computed mg, oldest first, with a spoken summary")
    func chart() async throws {
        let setup = try await makeSetup()

        #expect(setup.vm.chartPoints.map(\.value) == [1, 1.25, 1.5])
        #expect(setup.vm.chartUnit == "mg")
        #expect(setup.vm.chartSummary.hasPrefix("3 doses since"))
        #expect(setup.vm.chartSummary.hasSuffix("Latest 1.5 mg."))
    }

    @Test("Editing a dose recomputes mg against the concentration it was logged at")
    func editUsesSnapshot() async throws {
        let setup = try await makeSetup()
        // A new vial, mixed stronger, must not rewrite the old dose.
        setup.medication.setVialMix(amountMg: 20, diluentMl: 2)
        try await setup.medications.update(setup.medication)
        let dose = try #require(setup.vm.doses.last)
        var draft = DoseEntryDraft(editing: dose, medication: setup.medication)
        #expect(draft.amountText == "0.2")
        draft.amountText = "0.4"
        draft.note = "  left side  "

        let saved = await setup.vm.update(dose, with: draft)

        #expect(saved)
        #expect(dose.computedMg == 2)
        #expect(dose.note == "left side")
        #expect(dose.syncStatus == .pending)
        #expect(setup.vm.rows.last?.amountText == "0.4 mL (2 mg)")
    }

    @Test("Deleting a dose removes it from the history")
    func deleteDose() async throws {
        let setup = try await makeSetup()
        let newest = try #require(setup.vm.doses.first)

        await setup.vm.delete(newest)

        #expect(setup.vm.rows.count == 2)
        #expect(try await setup.doses.fetch(for: setup.medication).count == 2)
    }

    @Test("Editing the medication changes its name, concentration and usual dose")
    func editMedication() async throws {
        let setup = try await makeSetup()
        var draft = MedicationDraft(medication: setup.medication, usualDose: setup.vm.usualDose)
        #expect(draft.unit == .mL)
        #expect(draft.concentrationMode == .vialMix)
        #expect(draft.vialAmountText == "10")
        #expect(draft.usualDoseText == "0.3")
        draft.name = "Renamed"
        draft.concentrationMode = .direct
        draft.concentrationText = "4"
        draft.usualDoseText = "0.5"

        let saved = await setup.vm.saveEdits(draft)

        #expect(saved)
        #expect(setup.medication.name == "Renamed")
        #expect(setup.medication.effectiveConcentrationMgPerMl == 4)
        #expect(setup.medication.vialAmountMg == nil)
        #expect(setup.vm.usualDoseText == "Usual dose 0.5 mL (2 mg)")
        // Past doses keep the mg they were logged with.
        #expect(setup.vm.rows.first?.amountText == "0.3 mL (1.5 mg)")
    }

    @Test("Archive and unarchive flip the flag and keep the history")
    func archive() async throws {
        let setup = try await makeSetup()

        await setup.vm.archive()
        #expect(setup.medication.isArchived)
        #expect(try await setup.medications.fetchActive().isEmpty)
        #expect(setup.vm.rows.count == 3)

        await setup.vm.unarchive()
        #expect(!setup.medication.isArchived)
    }
}
