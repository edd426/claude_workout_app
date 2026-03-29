import Foundation

enum SyncStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case synced
}
