import Foundation
import SwiftData

/// The unit a dose was entered in (#164).
enum DoseUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case mg
    case mcg
    case g
    case tablet
    case mL
    /// U-100 insulin-syringe units: 100 units = 1 mL.
    case syringeUnits
    /// International units. Logged as entered; never converted to mg.
    case IU

    var id: String { rawValue }

    /// Short label for an amount, e.g. "2.5 mg", "50 units".
    var symbol: String {
        switch self {
        case .mg: return "mg"
        case .mcg: return "mcg"
        case .g: return "g"
        case .tablet: return "tablets"
        case .mL: return "mL"
        case .syringeUnits: return "units"
        case .IU: return "IU"
        }
    }
}

/// One logged dose of a `Medication` (#164).
///
/// Stores the raw entry (`amount` in `unit`) and, where it can be computed,
/// the mg it represents. `concentrationMgPerMlAtLog` is the medication's
/// concentration at the moment of logging: a later vial with a different mix
/// changes the medication, never this record. Use `init(logging:unit:of:...)`
/// to log, and `revise(amount:unit:)` to edit, so `computedMg` stays honest.
///
/// Schema V5, a NEW model.
@Model
final class MedicationDose: SyncableModel {
    @Attribute(.unique) var id: UUID
    var medication: Medication?
    var takenAt: Date
    var amount: Double
    var unitRaw: String
    /// Nil for IU, and for mL / syringe units logged with no known concentration.
    var computedMg: Double?
    /// Snapshot of the medication's concentration when this dose was logged.
    var concentrationMgPerMlAtLog: Double?
    var note: String?
    var syncStatusRaw: String = "pending"
    var lastModified: Date

    /// Nil only for a unit written by a newer build.
    var unit: DoseUnit? {
        DoseUnit(rawValue: unitRaw)
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    /// Full-field initializer, for restore and import. Computes nothing.
    init(
        id: UUID = UUID(),
        medication: Medication?,
        takenAt: Date = .now,
        amount: Double,
        unitRaw: String,
        computedMg: Double?,
        concentrationMgPerMlAtLog: Double?,
        note: String? = nil,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.medication = medication
        self.takenAt = takenAt
        self.amount = amount
        self.unitRaw = unitRaw
        self.computedMg = computedMg
        self.concentrationMgPerMlAtLog = concentrationMgPerMlAtLog
        self.note = note
        self.syncStatusRaw = syncStatus.rawValue
        self.lastModified = lastModified
    }

    /// Logs a dose now: snapshots the medication's current concentration and
    /// computes mg from it and the tablet strength.
    convenience init(
        logging amount: Double,
        unit: DoseUnit,
        of medication: Medication,
        takenAt: Date = .now,
        note: String? = nil
    ) {
        let concentration = medication.effectiveConcentrationMgPerMl
        self.init(
            medication: medication,
            takenAt: takenAt,
            amount: amount,
            unitRaw: unit.rawValue,
            computedMg: DoseCalculator.computedMg(
                amount: amount,
                unit: unit,
                tabletStrengthMg: medication.tabletStrengthMg,
                concentrationMgPerMl: concentration
            ),
            concentrationMgPerMlAtLog: concentration,
            note: note
        )
    }

    /// Edits the amount or unit and recomputes mg against the concentration
    /// SNAPSHOTTED at log time, not the medication's current one.
    ///
    /// Tablet strength is not snapshotted (the data model carries only the
    /// concentration), so revising a tablet dose uses the medication's current
    /// strength. Persist through `MedicationDoseRepository.update`.
    func revise(amount: Double, unit: DoseUnit) {
        self.amount = amount
        unitRaw = unit.rawValue
        computedMg = DoseCalculator.computedMg(
            amount: amount,
            unit: unit,
            tabletStrengthMg: medication?.tabletStrengthMg,
            concentrationMgPerMl: concentrationMgPerMlAtLog
        )
    }
}
