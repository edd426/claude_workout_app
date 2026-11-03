import Foundation

/// The unit a medication is dosed in, as the Add sheet offers it: one flat
/// list that maps onto the model's `DoseForm` (#164).
enum MedicationUnitChoice: String, CaseIterable, Identifiable, Sendable {
    case mg, mcg, g, tablets, mL, syringeUnits, IU

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mg: return "mg"
        case .mcg: return "mcg"
        case .g: return "g"
        case .tablets: return "tablets"
        case .mL: return "mL"
        case .syringeUnits: return "units (U-100)"
        case .IU: return "IU"
        }
    }

    var doseForm: DoseForm {
        switch self {
        case .mg, .mcg, .g: return .mass
        case .tablets: return .tablet
        case .mL, .syringeUnits: return .liquid
        case .IU: return .units
        }
    }

    /// The unit a dose is entered in.
    var doseUnit: DoseUnit {
        switch self {
        case .mg: return .mg
        case .mcg: return .mcg
        case .g: return .g
        case .tablets: return .tablet
        case .mL: return .mL
        case .syringeUnits: return .syringeUnits
        case .IU: return .IU
        }
    }

    var massUnit: MassUnit? {
        switch self {
        case .mg: return .mg
        case .mcg: return .mcg
        case .g: return .g
        default: return nil
        }
    }

    /// Volumes can convert to mg through a concentration.
    var takesConcentration: Bool { doseForm == .liquid }

    init(medication: Medication, usualUnit: DoseUnit?) {
        switch medication.doseForm {
        case .mass:
            switch medication.massUnit {
            case .mg: self = .mg
            case .mcg: self = .mcg
            case .g: self = .g
            }
        case .tablet: self = .tablets
        case .liquid:
            self = medication.allowsSyringeUnits && usualUnit != .mL ? .syringeUnits : .mL
        case .units: self = .IU
        }
    }
}

/// How a liquid's concentration is known, if at all.
enum ConcentrationMode: String, CaseIterable, Identifiable, Sendable {
    case none, direct, vialMix

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .direct: return "mg per mL"
        case .vialMix: return "Mixed vial"
        }
    }
}

/// The Add / Edit medication sheet's state (#164). Text fields stay text so
/// a half-typed "0," is not rejected while typing; parsing happens on read.
struct MedicationDraft: Equatable, Sendable {
    var name = ""
    var unit: MedicationUnitChoice = .mg
    var usualDoseText = ""
    var tabletStrengthText = ""
    var concentrationMode: ConcentrationMode = .none
    var concentrationText = ""
    var vialAmountText = ""
    var diluentText = ""

    init() {}

    /// Prefills the sheet from an existing medication.
    @MainActor
    init(medication: Medication, usualDose: UsualDose?) {
        name = medication.name
        unit = MedicationUnitChoice(medication: medication, usualUnit: usualDose?.unit)
        if let usualDose, usualDose.unit == unit.doseUnit {
            usualDoseText = BodyFormat.number(usualDose.amount, maxFractionDigits: 3)
        }
        if let strength = medication.tabletStrengthMg {
            tabletStrengthText = BodyFormat.number(strength, maxFractionDigits: 3)
        }
        if let direct = medication.concentrationMgPerMl {
            concentrationMode = .direct
            concentrationText = BodyFormat.number(direct, maxFractionDigits: 3)
        } else if let vial = medication.vialAmountMg, let diluent = medication.diluentMl {
            concentrationMode = .vialMix
            vialAmountText = BodyFormat.number(vial, maxFractionDigits: 3)
            diluentText = BodyFormat.number(diluent, maxFractionDigits: 3)
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The usual dose as typed; nil when the field is empty or not a number.
    var usualDose: UsualDose? {
        guard let amount = BodyFormat.decimal(usualDoseText), amount > 0 else { return nil }
        return UsualDose(amount: amount, unit: unit.doseUnit)
    }

    var tabletStrengthMg: Double? {
        guard unit == .tablets else { return nil }
        return positive(tabletStrengthText)
    }

    /// The concentration the fields describe, nil when there is none or the
    /// fields are incomplete.
    var concentrationMgPerMl: Double? {
        guard unit.takesConcentration else { return nil }
        switch concentrationMode {
        case .none: return nil
        case .direct: return positive(concentrationText)
        case .vialMix:
            guard let vial = positive(vialAmountText), let diluent = positive(diluentText) else {
                return nil
            }
            return DoseCalculator.concentration(vialAmountMg: vial, diluentMl: diluent)
        }
    }

    /// What is wrong, in words, or nil when the draft can be saved.
    var validationMessage: String? {
        if trimmedName.isEmpty { return "Enter a name." }
        if !isBlank(usualDoseText), usualDose == nil {
            return "The usual dose must be a number above zero."
        }
        if unit == .tablets, !isBlank(tabletStrengthText), tabletStrengthMg == nil {
            return "The strength must be a number above zero."
        }
        if unit.takesConcentration {
            switch concentrationMode {
            case .none: break
            case .direct where concentrationMgPerMl == nil:
                return "Enter the concentration in mg per mL."
            case .vialMix where concentrationMgPerMl == nil:
                return "Enter the mg in the vial and the mL of liquid added."
            default: break
            }
        }
        return nil
    }

    var isValid: Bool { validationMessage == nil }

    /// "0.25 mL = 1.25 mg at 5 mg/mL", or nil when nothing converts.
    var dosePreview: String? {
        guard let dose = usualDose else { return nil }
        let mg = DoseCalculator.computedMg(
            amount: dose.amount,
            unit: dose.unit,
            tabletStrengthMg: tabletStrengthMg,
            concentrationMgPerMl: concentrationMgPerMl
        )
        guard let mg, MedicationDoseFormatter.showsComputedMg(for: dose.unit) else { return nil }
        let formatter = MedicationDoseFormatter()
        var text = "\(formatter.amount(dose.amount, unit: dose.unit)) = \(BodyFormat.number(mg, maxFractionDigits: 3)) mg"
        if let concentration = concentrationMgPerMl {
            text += " at \(BodyFormat.number(concentration, maxFractionDigits: 3)) mg/mL"
        }
        return text
    }

    /// A new medication from the draft, or nil if it is not valid.
    @MainActor
    func makeMedication(now: Date = .now) -> Medication? {
        guard isValid else { return nil }
        let medication = Medication(name: trimmedName, doseForm: unit.doseForm, createdAt: now, lastModified: now)
        apply(to: medication)
        return medication
    }

    /// Writes the draft onto a medication. Persist with
    /// `MedicationRepository.update` (or `save` for a new one).
    @MainActor
    func apply(to medication: Medication) {
        medication.name = trimmedName
        medication.doseForm = unit.doseForm
        medication.massUnitRaw = unit.massUnit?.rawValue
        medication.tabletStrengthMg = tabletStrengthMg
        medication.allowsSyringeUnits = unit == .syringeUnits
        switch (unit.takesConcentration, concentrationMode) {
        case (true, .direct):
            medication.setDirectConcentration(concentrationMgPerMl)
        case (true, .vialMix):
            if let vial = positive(vialAmountText), let diluent = positive(diluentText) {
                medication.setVialMix(amountMg: vial, diluentMl: diluent)
            }
        default:
            medication.setDirectConcentration(nil)
        }
    }

    private func positive(_ text: String) -> Double? {
        guard let value = BodyFormat.decimal(text), value > 0 else { return nil }
        return value
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// The Log dose / Edit dose sheet's state (#164).
struct DoseEntryDraft: Equatable, Sendable {
    var amountText: String
    var unit: DoseUnit
    var takenAt: Date
    var note: String
    /// Make this the dose that one tap logs from now on.
    var makeUsual: Bool

    /// The units this medication can be entered in.
    let allowedUnits: [DoseUnit]
    /// The values mg is computed from: the medication's current ones for a
    /// new dose, the snapshot for an edit.
    let tabletStrengthMg: Double?
    let concentrationMgPerMl: Double?

    /// A new dose, starting from the default dose when there is one.
    @MainActor
    init(newDoseFor medication: Medication, defaultDose: UsualDose?, now: Date = .now) {
        amountText = defaultDose.map { BodyFormat.number($0.amount, maxFractionDigits: 3) } ?? ""
        unit = defaultDose?.unit ?? medication.defaultDoseUnit
        takenAt = now
        note = ""
        makeUsual = true
        allowedUnits = medication.allowedDoseUnits
        tabletStrengthMg = medication.tabletStrengthMg
        concentrationMgPerMl = medication.effectiveConcentrationMgPerMl
    }

    /// Editing a logged dose: mg recomputes against its snapshot.
    @MainActor
    init(editing dose: MedicationDose, medication: Medication) {
        amountText = BodyFormat.number(dose.amount, maxFractionDigits: 3)
        let unit = dose.unit ?? medication.defaultDoseUnit
        self.unit = unit
        takenAt = dose.takenAt
        note = dose.note ?? ""
        makeUsual = false
        var allowed = medication.allowedDoseUnits
        if !allowed.contains(unit) { allowed.insert(unit, at: 0) }
        allowedUnits = allowed
        tabletStrengthMg = dose.tabletStrengthMgAtLog
        concentrationMgPerMl = dose.concentrationMgPerMlAtLog
    }

    var amount: Double? {
        guard let value = BodyFormat.decimal(amountText), value > 0 else { return nil }
        return value
    }

    var isValid: Bool { amount != nil }

    var computedMg: Double? {
        guard let amount else { return nil }
        return DoseCalculator.computedMg(
            amount: amount, unit: unit,
            tabletStrengthMg: tabletStrengthMg,
            concentrationMgPerMl: concentrationMgPerMl
        )
    }

    /// "= 2.5 mg", shown under the amount for tablets and volumes.
    var computedMgText: String? {
        guard MedicationDoseFormatter.showsComputedMg(for: unit), amount != nil else { return nil }
        guard let mg = computedMg else {
            return unit == .tablet
                ? "Add a strength to the medication to see mg."
                : "Add a concentration to the medication to see mg."
        }
        return "= \(BodyFormat.number(mg, maxFractionDigits: 3)) mg"
    }
}
