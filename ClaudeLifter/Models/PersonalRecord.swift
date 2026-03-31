import Foundation
import SwiftData

enum PRType: String, Codable, Sendable {
    case heaviestWeight
    case mostRepsAtWeight
    case highest1RM
}

@Model
final class PersonalRecord {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var type: String  // Store PRType as String for SwiftData compatibility
    var value: Double
    var weight: Double?
    var reps: Int?
    var achievedAt: Date
    var workoutId: UUID
    var syncStatus: SyncStatus
    var lastModified: Date

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        type: PRType,
        value: Double,
        weight: Double? = nil,
        reps: Int? = nil,
        achievedAt: Date = .now,
        workoutId: UUID,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.type = type.rawValue
        self.value = value
        self.weight = weight
        self.reps = reps
        self.achievedAt = achievedAt
        self.workoutId = workoutId
        self.syncStatus = syncStatus
        self.lastModified = lastModified
    }

    var prType: PRType {
        PRType(rawValue: type) ?? .heaviestWeight
    }

    /// Brzycki formula: estimated 1RM from weight and reps.
    /// Returns nil if reps > 36 (formula becomes invalid/negative).
    static func estimated1RM(weight: Double, reps: Int) -> Double? {
        guard reps <= 36 else { return nil }
        return weight * (36.0 / (37.0 - Double(reps)))
    }
}
