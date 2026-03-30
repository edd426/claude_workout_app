import Foundation
import SwiftData

@Model
final class TrainingPreference {
    @Attribute(.unique) var id: UUID
    var key: String
    var value: String
    var createdAt: Date
    var updatedAt: Date
    var source: String?
    var syncStatus: SyncStatus = SyncStatus.pending
    var lastModified: Date = Date.now

    init(
        id: UUID = UUID(),
        key: String,
        value: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        source: String? = nil,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.syncStatus = syncStatus
        self.lastModified = lastModified
    }
}
