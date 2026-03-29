import Foundation
import SwiftData

@Model
final class AIChatMessage {
    @Attribute(.unique) var id: UUID
    var workoutId: UUID?
    var role: MessageRole
    var content: String
    var timestamp: Date
    var syncStatus: SyncStatus

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        workoutId: UUID? = nil,
        timestamp: Date = .now,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.workoutId = workoutId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.syncStatus = syncStatus
    }
}
