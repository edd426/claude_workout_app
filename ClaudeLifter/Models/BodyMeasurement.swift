import Foundation
import SwiftData

/// Where on the body a circumference was taken (#165).
///
/// Stored on `BodyMeasurement` as its raw string, so a site added later is a
/// new case here and nothing else: no schema change, no migration. Waist is
/// the only site the UI offers for now; the rest exist because Jefit's export
/// carries them and is the obvious import source.
enum MeasurementSite: String, Codable, CaseIterable, Sendable, Identifiable {
    case waist
    case hips
    case chest
    case arm
    case thigh
    case calf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .waist: return "Waist"
        case .hips: return "Hips"
        case .chest: return "Chest"
        case .arm: return "Arm"
        case .thigh: return "Thigh"
        case .calf: return "Calf"
        }
    }
}

/// One body circumference measurement (#165). Canonical unit is centimetres;
/// inches are a display conversion (`LengthConversion`).
///
/// Introduced in schema V5 as a NEW model. It deliberately has no relationship
/// to anything: a relationship would need a stored property on the other side,
/// and a property-only change cannot be versioned in this app (see the note on
/// `ClaudeLifterSchemaV4`).
@Model
final class BodyMeasurement: SyncableModel {
    @Attribute(.unique) var id: UUID
    /// Raw `MeasurementSite`. Kept as a string so a site written by a newer
    /// build survives a restore instead of being coerced.
    var siteRaw: String
    var valueCm: Double
    var recordedAt: Date
    var note: String?
    var syncStatusRaw: String = "pending"
    var lastModified: Date

    /// Nil only for a site this build does not know (written by a newer one).
    var site: MeasurementSite? {
        MeasurementSite(rawValue: siteRaw)
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        site: MeasurementSite,
        valueCm: Double,
        recordedAt: Date = .now,
        note: String? = nil,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.siteRaw = site.rawValue
        self.valueCm = valueCm
        self.recordedAt = recordedAt
        self.note = note
        self.syncStatusRaw = syncStatus.rawValue
        self.lastModified = lastModified
    }
}
