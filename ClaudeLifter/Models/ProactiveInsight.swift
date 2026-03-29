import Foundation
import SwiftData

@Model
final class ProactiveInsight {
    @Attribute(.unique) var id: UUID
    var content: String
    var generatedAt: Date
    var isRead: Bool
    var type: InsightType

    init(
        id: UUID = UUID(),
        content: String,
        type: InsightType,
        generatedAt: Date = .now,
        isRead: Bool = false
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.generatedAt = generatedAt
        self.isRead = isRead
    }
}
