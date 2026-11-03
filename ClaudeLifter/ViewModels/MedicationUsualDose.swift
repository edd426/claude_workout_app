import Foundation

/// The dose a medication's one-tap **Log dose** button logs (#164).
struct UsualDose: Codable, Equatable, Sendable {
    let amount: Double
    let unit: DoseUnit
}

/// Where the usual dose lives.
///
/// Schema V5 has no default-dose field on `Medication`, and 1.9.0 makes no
/// model changes, so the usual dose is a per-device preference keyed by the
/// medication's id. It is a convenience, not history: when it is missing (a
/// restore onto a new phone, a medication that arrived by sync) the last
/// logged dose stands in, which is #164's "log the same as last time".
@MainActor
protocol MedicationUsualDoseStoring: AnyObject {
    func usualDose(for medicationID: UUID) -> UsualDose?
    /// Nil clears it.
    func setUsualDose(_ dose: UsualDose?, for medicationID: UUID)
}

@MainActor
final class UserDefaultsUsualDoseStore: MedicationUsualDoseStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func usualDose(for medicationID: UUID) -> UsualDose? {
        guard let data = defaults.data(forKey: key(medicationID)) else { return nil }
        return try? JSONDecoder().decode(UsualDose.self, from: data)
    }

    func setUsualDose(_ dose: UsualDose?, for medicationID: UUID) {
        guard let dose, let data = try? JSONEncoder().encode(dose) else {
            defaults.removeObject(forKey: key(medicationID))
            return
        }
        defaults.set(data, forKey: key(medicationID))
    }

    private func key(_ id: UUID) -> String {
        "medicationUsualDose.\(id.uuidString)"
    }
}

extension Medication {
    /// The dose one tap logs: the usual dose if one is set, else the last
    /// dose logged. Nil when neither exists or the unit no longer fits the
    /// medication (its form was edited): the caller then asks for a dose.
    @MainActor
    func resolvedDefaultDose(
        usual: UsualDose?,
        lastDose: MedicationDose?
    ) -> UsualDose? {
        let allowed = allowedDoseUnits
        if let usual, allowed.contains(usual.unit), usual.amount > 0 {
            return usual
        }
        if let lastDose, let unit = lastDose.unit, allowed.contains(unit), lastDose.amount > 0 {
            return UsualDose(amount: lastDose.amount, unit: unit)
        }
        return nil
    }
}
