import Foundation
import SwiftData

/// How a medication's doses are entered (#164). Chosen per medication, because
/// the same number means different things for different medications.
enum DoseForm: String, Codable, CaseIterable, Sendable, Identifiable {
    /// mg / mcg / g, entered directly.
    case mass
    /// Count × strength per tablet (or capsule).
    case tablet
    /// Volume in mL, converted to mg through a concentration when one is known.
    case liquid
    /// IU or other units: logged as entered, never converted.
    case units

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mass: return "mg / mcg / g"
        case .tablet: return "Tablets / capsules"
        case .liquid: return "Liquid (mL)"
        case .units: return "IU / units"
        }
    }
}

/// The mass unit a `.mass` medication is entered in.
enum MassUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case mg
    case mcg
    case g

    var id: String { rawValue }

    /// The matching dose-entry unit.
    var doseUnit: DoseUnit {
        switch self {
        case .mg: return .mg
        case .mcg: return .mcg
        case .g: return .g
        }
    }
}

/// A user-defined medication (#164). The name is free text the user typed;
/// nothing is preset or suggested.
///
/// The UI archives a medication rather than deleting it, so its history
/// survives. `delete` exists on the repository only for restore.
///
/// Concentration, for `.liquid`: either `concentrationMgPerMl` directly, or a
/// vial the user mixed (`vialAmountMg` ÷ `diluentMl`). Use `setDirectConcentration`
/// / `setVialMix` so the two never disagree. A dose snapshots the concentration
/// and the tablet strength when it is logged (`MedicationDose.concentrationMgPerMlAtLog`,
/// `tabletStrengthMgAtLog`), so a new vial or a new prescription never
/// rewrites history.
///
/// Schema V5, a NEW model. The `doses` relationship is safe only because both
/// ends are new in V5; never add one to a model that existed in V1–V4.
@Model
final class Medication: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var doseFormRaw: String
    /// `.mass` only: the unit doses are entered in.
    var massUnitRaw: String?
    /// `.tablet` only: mg per tablet.
    var tabletStrengthMg: Double?
    /// `.liquid`: concentration entered directly. Takes precedence over a vial mix.
    var concentrationMgPerMl: Double?
    /// `.liquid`: mg in the vial the user mixed.
    var vialAmountMg: Double?
    /// `.liquid`: mL of diluent added to that vial.
    var diluentMl: Double?
    /// `.liquid`: allow entry in U-100 syringe units (100 units = 1 mL).
    var allowsSyringeUnits: Bool
    var isArchived: Bool
    var createdAt: Date
    var syncStatusRaw: String = "pending"
    var lastModified: Date

    @Relationship(deleteRule: .cascade, inverse: \MedicationDose.medication)
    var doses: [MedicationDose]

    /// Falls back to `.units` (logged as entered, never converted) for a form
    /// written by a newer build — the one reading that cannot misstate a dose.
    var doseForm: DoseForm {
        get { DoseForm(rawValue: doseFormRaw) ?? .units }
        set { doseFormRaw = newValue.rawValue }
    }

    var massUnit: MassUnit {
        get { massUnitRaw.flatMap(MassUnit.init(rawValue:)) ?? .mg }
        set { massUnitRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    /// The concentration a dose logged now would use: the direct value when
    /// set, otherwise the vial mix, otherwise nil (mL cannot convert to mg).
    var effectiveConcentrationMgPerMl: Double? {
        if let direct = concentrationMgPerMl, direct.isFinite, direct > 0 {
            return direct
        }
        guard let vialAmountMg, let diluentMl else { return nil }
        return DoseCalculator.concentration(vialAmountMg: vialAmountMg, diluentMl: diluentMl)
    }

    /// The units a dose of this medication may be entered in.
    var allowedDoseUnits: [DoseUnit] {
        switch doseForm {
        case .mass: return [.mg, .mcg, .g]
        case .tablet: return [.tablet]
        case .liquid: return allowsSyringeUnits ? [.mL, .syringeUnits] : [.mL]
        case .units: return [.IU]
        }
    }

    /// The unit a new dose entry starts in.
    var defaultDoseUnit: DoseUnit {
        switch doseForm {
        case .mass: return massUnit.doseUnit
        case .tablet: return .tablet
        case .liquid: return .mL
        case .units: return .IU
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        doseForm: DoseForm,
        massUnit: MassUnit? = nil,
        tabletStrengthMg: Double? = nil,
        concentrationMgPerMl: Double? = nil,
        vialAmountMg: Double? = nil,
        diluentMl: Double? = nil,
        allowsSyringeUnits: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.name = name
        self.doseFormRaw = doseForm.rawValue
        self.massUnitRaw = massUnit?.rawValue
        self.tabletStrengthMg = tabletStrengthMg
        self.concentrationMgPerMl = concentrationMgPerMl
        self.vialAmountMg = vialAmountMg
        self.diluentMl = diluentMl
        self.allowsSyringeUnits = allowsSyringeUnits
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.syncStatusRaw = syncStatus.rawValue
        self.lastModified = lastModified
        self.doses = []
    }

    /// Concentration entered directly; clears any vial mix so the two cannot
    /// disagree. Pass nil to clear it. Persist through `MedicationRepository.update`.
    func setDirectConcentration(_ mgPerMl: Double?) {
        concentrationMgPerMl = mgPerMl
        vialAmountMg = nil
        diluentMl = nil
    }

    /// Concentration from a vial the user mixed; clears any direct value.
    /// Persist through `MedicationRepository.update`.
    func setVialMix(amountMg: Double, diluentMl: Double) {
        concentrationMgPerMl = nil
        vialAmountMg = amountMg
        self.diluentMl = diluentMl
    }
}
