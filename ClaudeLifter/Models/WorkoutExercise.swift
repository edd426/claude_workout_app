import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var order: Int
    var notes: String?
    var restSeconds: Int

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade)
    var sets: [WorkoutSet]

    init(
        id: UUID = UUID(),
        order: Int,
        exercise: Exercise,
        notes: String? = nil,
        restSeconds: Int = 90
    ) {
        self.id = id
        self.order = order
        self.exercise = exercise
        self.notes = notes
        self.restSeconds = restSeconds
        self.sets = []
    }
}
