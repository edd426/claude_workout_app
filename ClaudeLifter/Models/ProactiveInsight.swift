import Foundation
import SwiftData

@Model
final class ProactiveInsight {
    @Attribute(.unique) var id: UUID
    var content: String
    var generatedAt: Date
    var isRead: Bool
    var type: InsightType
    var syncStatusRaw: String = "pending"
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
    var lastModified: Date = Date.now

    init(
        id: UUID = UUID(),
        content: String,
        type: InsightType,
        generatedAt: Date = .now,
        isRead: Bool = false,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.generatedAt = generatedAt
        self.isRead = isRead
        self.syncStatusRaw = syncStatus.rawValue
        self.lastModified = lastModified
    }
}
