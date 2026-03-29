import Foundation
import SwiftData

@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var order: Int
    var weight: Double?
    var weightUnit: WeightUnit
    var reps: Int?
    var isCompleted: Bool
    var completedAt: Date?
    var notes: String?

    init(
        id: UUID = UUID(),
        order: Int,
        weight: Double? = nil,
        weightUnit: WeightUnit = .kg,
        reps: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.order = order
        self.weight = weight
        self.weightUnit = weightUnit
        self.reps = reps
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.notes = notes
    }
}
