import Foundation
import SwiftData

@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var templateId: UUID?
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var notes: String?
    var syncStatus: SyncStatus
    var lastModified: Date

    @Relationship(deleteRule: .cascade)
    var exercises: [WorkoutExercise]

    init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        templateId: UUID? = nil,
        completedAt: Date? = nil,
        notes: String? = nil,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.syncStatus = syncStatus
        self.lastModified = lastModified
        self.exercises = []
    }
}
