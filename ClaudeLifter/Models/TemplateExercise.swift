import Foundation
import SwiftData

@Model
final class TemplateExercise {
    @Attribute(.unique) var id: UUID
    var order: Int
    var defaultSets: Int
    var defaultReps: Int
    var defaultWeight: Double?
    var defaultRestSeconds: Int
    var notes: String?

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    init(
        id: UUID = UUID(),
        order: Int,
        exercise: Exercise,
        defaultSets: Int,
        defaultReps: Int,
        defaultWeight: Double? = nil,
        defaultRestSeconds: Int = 90,
        notes: String? = nil
    ) {
        self.id = id
        self.order = order
        self.exercise = exercise
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.defaultWeight = defaultWeight
        self.defaultRestSeconds = defaultRestSeconds
        self.notes = notes
    }
}
