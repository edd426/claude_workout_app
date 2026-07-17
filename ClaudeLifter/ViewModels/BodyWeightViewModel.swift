import Foundation
import Observation

/// Drives the Home quick-log card and entry sheet (issue #80).
///
/// Canonical storage is kilograms; this VM converts to/from the user's display
/// unit at the edges. HealthKit is strictly best-effort: a declined permission
/// or failed write never blocks the local entry.
@Observable
@MainActor
final class BodyWeightViewModel {
    private let repository: any BodyWeightRepository
    private let healthKit: any HealthKitServiceProtocol
    private let settings: SettingsManager

    var latest: BodyWeightEntry?
    private(set) var recentEntries: [BodyWeightEntry] = []
    var errorMessage: String?

    init(
        repository: any BodyWeightRepository,
        healthKit: any HealthKitServiceProtocol,
        settings: SettingsManager
    ) {
        self.repository = repository
        self.healthKit = healthKit
        self.settings = settings
    }

    var displayUnit: WeightUnit { settings.weightUnit }

    /// Latest weight converted to the display unit, for pre-filling the sheet.
    var latestDisplayWeight: Double? {
        latest.map { WeightUnit.kg.convert($0.weightKg, to: displayUnit) }
    }

    /// Change in display units between the latest entry and the oldest entry
    /// inside the trailing window. Nil until two entries span the window.
    func delta(days: Int) -> Double? {
        guard let latest else { return nil }
        let windowStart = Date(timeIntervalSinceNow: -Double(days) * 86_400)
        let inWindow = recentEntries.filter { $0.recordedAt >= windowStart }
        guard let oldest = inWindow.first, oldest.id != latest.id else { return nil }
        return WeightUnit.kg.convert(latest.weightKg - oldest.weightKg, to: displayUnit)
    }

    func load() async {
        latest = try? await repository.fetchLatest()
        recentEntries = (try? await repository.fetchRange(
            from: Date(timeIntervalSinceNow: -30 * 86_400), to: .now
        )) ?? []
    }

    /// Log a weight typed in the given unit. Saves locally first (always), then
    /// mirrors to HealthKit and back-fills the sample UUID for import dedup.
    func logWeight(_ value: Double, unit: WeightUnit) async {
        errorMessage = nil
        let kilograms = unit.convert(value, to: .kg)
        let entry = BodyWeightEntry(weightKg: kilograms, recordedAt: .now, source: "manual")
        do {
            try await repository.save(entry)
        } catch {
            errorMessage = "Could not save weight: \(error.localizedDescription)"
            return
        }

        if healthKit.isAvailable {
            try? await healthKit.requestAuthorization()
            if let sampleUUID = try? await healthKit.writeBodyMass(
                kilograms: kilograms, date: entry.recordedAt
            ) {
                entry.healthKitSampleUUID = sampleUUID
                try? await repository.save(entry)
            }
        }

        await load()
    }

    /// Pull new samples from Health (scale apps, manual Health entries) into the
    /// local store, deduplicated by sample UUID — which also skips our own writes.
    func importFromHealthKit() async {
        guard healthKit.isAvailable else { return }
        guard let samples = try? await healthKit.fetchNewBodyMassSamples() else { return }
        for sample in samples {
            if (try? await repository.exists(healthKitSampleUUID: sample.uuid)) == true {
                continue
            }
            let entry = BodyWeightEntry(
                weightKg: sample.kilograms,
                recordedAt: sample.date,
                source: "healthkit",
                healthKitSampleUUID: sample.uuid
            )
            try? await repository.save(entry)
        }
        await load()
    }
}
