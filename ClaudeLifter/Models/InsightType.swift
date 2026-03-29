import Foundation

enum InsightType: String, Codable, CaseIterable, Sendable {
    case suggestion
    case warning
    case encouragement
}
