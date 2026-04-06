import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var force: String?
    var level: String?
    var mechanic: String?
    var equipment: String?
    var instructions: [String]
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var isCustom: Bool
    var externalId: String?
    var notes: String?
    var imageURL: String?
    var photoURL: String?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseTag.exercise)
    var tags: [ExerciseTag]

    init(
        id: UUID = UUID(),
        name: String,
        force: String? = nil,
        level: String? = nil,
        mechanic: String? = nil,
        equipment: String? = nil,
        instructions: [String] = [],
        primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [],
        isCustom: Bool = false,
        externalId: String? = nil,
        notes: String? = nil,
        imageURL: String? = nil,
        photoURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.force = force
        self.level = level
        self.mechanic = mechanic
        self.equipment = equipment
        self.instructions = instructions
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.isCustom = isCustom
        self.externalId = externalId
        self.notes = notes
        self.imageURL = imageURL
        self.photoURL = photoURL
        self.tags = []
    }
}
