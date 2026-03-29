import Foundation
import SwiftData

@Model
final class ExerciseTag {
    @Attribute(.unique) var id: UUID
    var category: String
    var value: String

    init(id: UUID = UUID(), category: String, value: String) {
        self.id = id
        self.category = category
        self.value = value
    }
}
