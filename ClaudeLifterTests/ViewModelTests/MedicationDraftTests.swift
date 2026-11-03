import Foundation
import Testing
@testable import ClaudeLifter

@Suite("MedicationDraft")
@MainActor
struct MedicationDraftTests {
    private func draft(_ unit: MedicationUnitChoice, dose: String = "1") -> MedicationDraft {
        var draft = MedicationDraft()
        draft.name = "Medication"
        draft.unit = unit
        draft.usualDoseText = dose
        return draft
    }

    @Test("Every unit choice maps onto the model's dose form", arguments: [
        (MedicationUnitChoice.mg, DoseForm.mass, DoseUnit.mg),
        (.mcg, .mass, .mcg),
        (.g, .mass, .g),
        (.tablets, .tablet, .tablet),
        (.mL, .liquid, .mL),
        (.syringeUnits, .liquid, .syringeUnits),
        (.IU, .units, .IU),
    ])
    func unitMapping(choice: MedicationUnitChoice, form: DoseForm, unit: DoseUnit) throws {
        let medication = try #require(draft(choice).makeMedication())
        #expect(medication.doseForm == form)
        #expect(medication.allowedDoseUnits.contains(unit))
        #expect(draft(choice).usualDose == UsualDose(amount: 1, unit: unit))
        // And back again, for the Edit sheet.
        #expect(MedicationUnitChoice(medication: medication, usualUnit: unit) == choice)
    }

    @Test("A mixed vial gives a concentration and a live mg preview")
    func vialMixPreview() {
        var draft = draft(.mL, dose: "0.5")
        draft.concentrationMode = .vialMix
        draft.vialAmountText = "10"
        draft.diluentText = "2"

        #expect(draft.concentrationMgPerMl == 5)
        #expect(draft.dosePreview == "0.5 mL = 2.5 mg at 5 mg/mL")
        let medication = draft.makeMedication()
        #expect(medication?.vialAmountMg == 10)
        #expect(medication?.diluentMl == 2)
        #expect(medication?.concentrationMgPerMl == nil)
    }

    @Test("A concentration typed directly is stored directly")
    func directConcentration() {
        var draft = draft(.syringeUnits, dose: "20")
        draft.concentrationMode = .direct
        draft.concentrationText = "2,5"

        #expect(draft.dosePreview == "20 units = 0.5 mg at 2.5 mg/mL")
        let medication = draft.makeMedication()
        #expect(medication?.concentrationMgPerMl == 2.5)
        #expect(medication?.allowsSyringeUnits == true)
    }

    @Test("Tablets preview count × strength")
    func tabletPreview() {
        var draft = draft(.tablets, dose: "1.5")
        draft.tabletStrengthText = "50"
        #expect(draft.dosePreview == "1.5 tablets = 75 mg")
    }

    @Test("Concentration fields are ignored for units that cannot use them")
    func concentrationOnlyForLiquids() {
        var draft = draft(.mg)
        draft.concentrationMode = .vialMix
        draft.vialAmountText = "10"
        draft.diluentText = "2"
        draft.tabletStrengthText = "50"

        #expect(draft.isValid)
        #expect(draft.concentrationMgPerMl == nil)
        #expect(draft.tabletStrengthMg == nil)
        #expect(draft.dosePreview == nil)
    }

    @Test("Validation names the problem", arguments: [
        ("", "1", ConcentrationMode.none, "", "", "Enter a name."),
        ("Name", "abc", .none, "", "", "The usual dose must be a number above zero."),
        ("Name", "0", .none, "", "", "The usual dose must be a number above zero."),
        ("Name", "1", .vialMix, "10", "", "Enter the mg in the vial and the mL of liquid added."),
        ("Name", "1", .direct, "", "", "Enter the concentration in mg per mL."),
    ])
    func validation(name: String, dose: String, mode: ConcentrationMode, vial: String, diluent: String, message: String) {
        var draft = MedicationDraft()
        draft.name = name
        draft.unit = .mL
        draft.usualDoseText = dose
        draft.concentrationMode = mode
        draft.vialAmountText = vial
        draft.diluentText = diluent
        draft.concentrationText = ""

        #expect(draft.validationMessage == message)
        #expect(draft.makeMedication() == nil)
    }

    @Test("The usual dose is optional")
    func usualDoseOptional() {
        let draft = draft(.mg, dose: "")
        #expect(draft.isValid)
        #expect(draft.usualDose == nil)
    }

    @Test("A new-dose draft without a concentration says how to get mg")
    func doseDraftWithoutConcentration() {
        let medication = Medication(name: "Plain", doseForm: .liquid)
        var dose = DoseEntryDraft(newDoseFor: medication, defaultDose: nil)
        #expect(dose.unit == .mL)
        #expect(dose.computedMgText == nil)
        dose.amountText = "1"
        #expect(dose.computedMgText == "Add a concentration to the medication to see mg.")
        #expect(dose.isValid)
    }
}
