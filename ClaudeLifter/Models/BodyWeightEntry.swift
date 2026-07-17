import Foundation
import SwiftData

/// A single body-weight measurement. Canonical unit is kilograms; display
/// converts per the global weight-unit setting.
///
/// Introduced in schema V2 (issue #80). `healthKitSampleUUID` carries the
/// HKQuantitySample UUID for entries imported from HealthKit so re-imports
/// dedup; manual entries leave it nil.
@Model
final class BodyWeightEntry: SyncableModel {
    @Attribute(.unique) var id: UUID
    var weightKg: Double
    var recordedAt: Date
    var source: String  // "manual" | "healthkit"
    var healthKitSampleUUID: UUID?
    var syncStatusRaw: String = "pending"
    var lastModified: Date

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        weightKg: Double,
        recordedAt: Date = .now,
        source: String = "manual",
        healthKitSampleUUID: UUID? = nil,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.weightKg = weightKg
        self.recordedAt = recordedAt
        self.source = source
        self.healthKitSampleUUID = healthKitSampleUUID
        self.syncStatusRaw = syncStatus.rawValue
        self.lastModified = lastModified
    }
}
