import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// Medication and dose behaviour (#164): concentration sources, what a dose
/// snapshots when it is logged, and why history never moves afterwards.
@Suite("Medication Model Tests")
@MainActor
struct MedicationModelTests {

    // MARK: - Concentration

    @Test("A vial mix gives the effective concentration: 10 mg + 2 mL → 5 mg/mL")
    func vialMixIsEffectiveConcentration() {
        let medication = Medication(name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2)
        #expect(medication.effectiveConcentrationMgPerMl == 5)
    }

    @Test("A directly entered concentration is used as is")
    func directConcentration() {
        let medication = Medication(name: "Syrup", doseForm: .liquid, concentrationMgPerMl: 2.5)
        #expect(medication.effectiveConcentrationMgPerMl == 2.5)
    }

    @Test("Without a concentration or a complete vial mix, mL cannot convert")
    func noConcentration() {
        #expect(Medication(name: "A", doseForm: .liquid).effectiveConcentrationMgPerMl == nil)
        #expect(Medication(name: "B", doseForm: .liquid, vialAmountMg: 10).effectiveConcentrationMgPerMl == nil)
        #expect(Medication(name: "C", doseForm: .liquid, vialAmountMg: 10, diluentMl: 0).effectiveConcentrationMgPerMl == nil)
    }

    @Test("Setting one concentration source clears the other")
    func concentrationSourcesAreExclusive() {
        let medication = Medication(name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2)

        medication.setDirectConcentration(4)
        #expect(medication.vialAmountMg == nil)
        #expect(medication.diluentMl == nil)
        #expect(medication.effectiveConcentrationMgPerMl == 4)

        medication.setVialMix(amountMg: 20, diluentMl: 2)
        #expect(medication.concentrationMgPerMl == nil)
        #expect(medication.effectiveConcentrationMgPerMl == 10)
    }

    // MARK: - Entry units

    @Test("Each dose form offers its own entry units")
    func allowedUnits() {
        #expect(Medication(name: "m", doseForm: .mass, massUnit: .mcg).defaultDoseUnit == .mcg)
        #expect(Medication(name: "t", doseForm: .tablet, tabletStrengthMg: 50).allowedDoseUnits == [.tablet])
        #expect(Medication(name: "l", doseForm: .liquid).allowedDoseUnits == [.mL])
        #expect(Medication(name: "s", doseForm: .liquid, allowsSyringeUnits: true).allowedDoseUnits == [.mL, .syringeUnits])
        #expect(Medication(name: "i", doseForm: .units).allowedDoseUnits == [.IU])
    }

    @Test("An unknown dose form from a newer build reads as units, which never converts")
    func unknownDoseFormFallsBackToUnits() {
        let medication = Medication(name: "x", doseForm: .mass)
        medication.doseFormRaw = "patch"
        #expect(medication.doseForm == .units)
        #expect(medication.doseFormRaw == "patch")
    }

    // MARK: - Logging snapshots

    @Test("A logged dose stores the raw entry, its computed mg, and the concentration at log time")
    func loggingSnapshotsConcentration() {
        let medication = Medication(name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2, allowsSyringeUnits: true)

        let dose = MedicationDose(logging: 50, unit: .syringeUnits, of: medication)

        #expect(dose.amount == 50)
        #expect(dose.unit == .syringeUnits)
        #expect(dose.computedMg == 2.5)
        #expect(dose.concentrationMgPerMlAtLog == 5)
    }

    @Test("Changing a medication's concentration does not change mg already computed on past doses")
    func newVialDoesNotRewriteHistory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let medication = Medication(name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2)
        context.insert(medication)
        let past = MedicationDose(logging: 0.5, unit: .mL, of: medication)
        context.insert(past)
        try context.save()

        // A new vial, mixed stronger.
        medication.setVialMix(amountMg: 20, diluentMl: 2)
        let today = MedicationDose(logging: 0.5, unit: .mL, of: medication)
        context.insert(today)
        try context.save()

        #expect(past.computedMg == 2.5)
        #expect(past.concentrationMgPerMlAtLog == 5)
        #expect(today.computedMg == 5)
        #expect(today.concentrationMgPerMlAtLog == 10)
    }

    @Test("Revising a past dose recomputes against its own snapshotted concentration")
    func reviseUsesSnapshot() {
        let medication = Medication(name: "Vial A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2)
        let dose = MedicationDose(logging: 0.5, unit: .mL, of: medication)
        medication.setVialMix(amountMg: 20, diluentMl: 2)

        dose.revise(amount: 0.4, unit: .mL)

        #expect(dose.amount == 0.4)
        #expect(dose.computedMg == 2)  // 0.4 mL × 5 mg/mL, not × 10
    }

    @Test("A tablet dose computes from the strength on file, and snapshots that strength")
    func tabletDose() {
        let medication = Medication(name: "Tabs", doseForm: .tablet, tabletStrengthMg: 50)
        let dose = MedicationDose(logging: 1.5, unit: .tablet, of: medication)
        #expect(dose.computedMg == 75)
        #expect(dose.tabletStrengthMgAtLog == 50)
        #expect(dose.concentrationMgPerMlAtLog == nil)
    }

    @Test("Changing a medication's tablet strength later does not change a past dose's computed mg")
    func newStrengthDoesNotRewriteHistory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let medication = Medication(name: "Tabs", doseForm: .tablet, tabletStrengthMg: 50)
        context.insert(medication)
        let past = MedicationDose(logging: 1.5, unit: .tablet, of: medication)
        context.insert(past)
        try context.save()

        // A new prescription, half the strength.
        medication.tabletStrengthMg = 25
        let today = MedicationDose(logging: 1.5, unit: .tablet, of: medication)
        context.insert(today)
        try context.save()

        #expect(past.computedMg == 75)
        #expect(past.tabletStrengthMgAtLog == 50)
        #expect(today.computedMg == 37.5)
        #expect(today.tabletStrengthMgAtLog == 25)
    }

    @Test("Editing a past tablet dose recomputes with its snapshotted strength, not today's")
    func reviseTabletUsesSnapshot() {
        let medication = Medication(name: "Tabs", doseForm: .tablet, tabletStrengthMg: 50)
        let dose = MedicationDose(logging: 1, unit: .tablet, of: medication)
        medication.tabletStrengthMg = 25

        dose.revise(amount: 2, unit: .tablet)

        #expect(dose.amount == 2)
        #expect(dose.computedMg == 100)  // 2 × 50 mg as logged, not 2 × 25
    }

    @Test("An IU dose is stored as entered with no computed mg")
    func internationalUnitDose() {
        let medication = Medication(name: "Vit D", doseForm: .units)
        let dose = MedicationDose(logging: 2000, unit: .IU, of: medication)
        #expect(dose.amount == 2000)
        #expect(dose.computedMg == nil)
    }
}
