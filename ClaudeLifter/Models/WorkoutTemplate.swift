import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var lastPerformedAt: Date?
    var timesPerformed: Int

    var syncStatusRaw: String = "pending"
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
    var lastModified: Date = Date.now

    @Relationship(deleteRule: .cascade)
    var exercises: [TemplateExercise]

    init(
        id: UUID = UUID(),
        name: String,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastPerformedAt: Date? = nil,
        timesPerformed: Int = 0,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastPerformedAt = lastPerformedAt
        self.timesPerformed = timesPerformed
        self.syncStatusRaw = syncStatus.rawValue
        self.lastModified = lastModified
        self.exercises = []
    }
}
