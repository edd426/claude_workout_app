import Foundation

enum MessageRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case system
}
