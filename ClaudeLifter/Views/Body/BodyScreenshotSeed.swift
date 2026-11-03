#if DEBUG
import Foundation

/// Synthetic Body-tab data for screenshots and UI tests: never anyone's real
/// numbers. Runs only in a DEBUG build launched with both `-UITesting` (the
/// in-memory store) and `-seedBodyData`, so it can never touch a real store.
@MainActor
enum BodyScreenshotSeed {
    private static var hasSeeded = false

    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITesting") && arguments.contains("-seedBodyData")
    }

    static func seedIfRequested(_ deps: DependencyContainer) async {
        guard isRequested, !hasSeeded else { return }
        hasSeeded = true
        do {
            try await seedWeights(deps)
            try await seedWaist(deps)
            try await seedMedications(deps)
        } catch {
            assertionFailure("Body screenshot seed failed: \(error)")
        }
    }

    private static let day: TimeInterval = 86_400

    private static func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        let date = start.addingTimeInterval(-Double(daysAgo) * day)
        return date.addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    /// 120 days drifting down about 0.2 kg a week, with day-to-day noise and
    /// gaps; the last weigh-in two days ago.
    private static func seedWeights(_ deps: DependencyContainer) async throws {
        for daysAgo in stride(from: 120, through: 2, by: -1) where daysAgo % 5 != 3 {
            let trend = 84.0 - Double(120 - daysAgo) * 0.03
            let noise = sin(Double(daysAgo) * 1.7) * 0.45
            try await deps.bodyWeightRepository.save(BodyWeightEntry(
                weightKg: ((trend + noise) * 10).rounded() / 10,
                recordedAt: at(daysAgo: daysAgo, hour: 7, minute: 30),
                source: "manual"
            ))
        }
        deps.settings.weightGoalPercentPerWeek = -0.3
        deps.settings.heightCm = 178
    }

    /// Monthly waist, the latest 12 days ago.
    private static func seedWaist(_ deps: DependencyContainer) async throws {
        let values = [96.0, 95.2, 94.5, 93.6, 92.8, 92.1]
        for (index, value) in values.enumerated() {
            let daysAgo = 12 + (values.count - 1 - index) * 30
            try await deps.bodyMeasurementRepository.save(BodyMeasurement(
                site: .waist, valueCm: value, recordedAt: at(daysAgo: daysAgo, hour: 7)
            ))
        }
    }

    private static func seedMedications(_ deps: DependencyContainer) async throws {
        let usual = UserDefaultsUsualDoseStore()

        let liquid = Medication(name: "Medication A", doseForm: .liquid, vialAmountMg: 10, diluentMl: 2)
        try await deps.medicationRepository.save(liquid)
        for (weeksAgo, amount) in [(5, 0.2), (4, 0.2), (3, 0.25), (2, 0.25), (1, 0.25)] {
            try await deps.medicationDoseRepository.save(MedicationDose(
                logging: amount, unit: .mL, of: liquid,
                takenAt: at(daysAgo: weeksAgo * 7 + 1, hour: 21, minute: 10)
            ))
        }
        try await deps.medicationDoseRepository.save(MedicationDose(
            logging: 0.25, unit: .mL, of: liquid, takenAt: at(daysAgo: 1, hour: 21, minute: 10)
        ))
        usual.setUsualDose(UsualDose(amount: 0.25, unit: .mL), for: liquid.id)

        let tablet = Medication(name: "Medication B", doseForm: .tablet, tabletStrengthMg: 50)
        try await deps.medicationRepository.save(tablet)
        for daysAgo in (0...6).reversed() {
            try await deps.medicationDoseRepository.save(MedicationDose(
                logging: 1, unit: .tablet, of: tablet, takenAt: at(daysAgo: daysAgo, hour: 8, minute: 5)
            ))
        }
        usual.setUsualDose(UsualDose(amount: 1, unit: .tablet), for: tablet.id)

        let units = Medication(name: "Supplement C", doseForm: .units)
        try await deps.medicationRepository.save(units)
        usual.setUsualDose(UsualDose(amount: 1000, unit: .IU), for: units.id)
    }
}
#endif
