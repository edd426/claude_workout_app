import Foundation
import SwiftData

@Model
final class AIChatMessage {
    @Attribute(.unique) var id: UUID
    var workoutId: UUID?
    var conversationId: UUID?
    var role: MessageRole
    var content: String
    var timestamp: Date
    var syncStatusRaw: String
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        workoutId: UUID? = nil,
        conversationId: UUID? = nil,
        timestamp: Date = .now,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.workoutId = workoutId
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.syncStatusRaw = syncStatus.rawValue
    }
}
