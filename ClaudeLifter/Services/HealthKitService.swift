import Foundation
import HealthKit

/// One body-mass sample from HealthKit, decoupled from HKQuantitySample so the
/// ViewModel and tests never touch HealthKit types.
struct HealthKitBodyMassSample: Sendable, Equatable {
    let uuid: UUID
    let kilograms: Double
    let date: Date
}

@MainActor
protocol HealthKitServiceProtocol {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    /// Write a bodyMass sample and return its UUID. The caller stores the UUID
    /// on the entry so the next anchored import recognises our own write and
    /// doesn't re-import it as a duplicate.
    func writeBodyMass(kilograms: Double, date: Date) async throws -> UUID
    /// Body-mass samples added to Health since the last stored anchor.
    func fetchNewBodyMassSamples() async throws -> [HealthKitBodyMassSample]
}

@MainActor
final class HealthKitService: HealthKitServiceProtocol {
    private let store = HKHealthStore()
    private let bodyMassType = HKQuantityType(.bodyMass)
    private let anchorKey = "healthKitBodyMassAnchor"

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(
            toShare: [bodyMassType],
            read: [bodyMassType]
        )
    }

    func writeBodyMass(kilograms: Double, date: Date) async throws -> UUID {
        let quantity = HKQuantity(
            unit: .gramUnit(with: .kilo),
            doubleValue: kilograms
        )
        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: quantity,
            start: date,
            end: date
        )
        try await store.save(sample)
        return sample.uuid
    }

    func fetchNewBodyMassSamples() async throws -> [HealthKitBodyMassSample] {
        let previousAnchor = loadAnchor()

        let (samples, newAnchor) = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<([HKSample], HKQueryAnchor?), Error>) in
            let query = HKAnchoredObjectQuery(
                type: bodyMassType,
                predicate: nil,
                anchor: previousAnchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples ?? [], newAnchor))
                }
            }
            store.execute(query)
        }

        if let newAnchor {
            saveAnchor(newAnchor)
        }

        return samples.compactMap { sample in
            guard let quantity = (sample as? HKQuantitySample)?.quantity else { return nil }
            return HealthKitBodyMassSample(
                uuid: sample.uuid,
                kilograms: quantity.doubleValue(for: .gramUnit(with: .kilo)),
                date: sample.startDate
            )
        }
    }

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: anchor, requiringSecureCoding: true
        ) else { return }
        UserDefaults.standard.set(data, forKey: anchorKey)
    }
}
