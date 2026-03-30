import Foundation

enum SyncError: Error, LocalizedError {
    case notConfigured
    case unauthorized
    case serverError(Int)
    case networkUnavailable
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sync server is not configured. Please set a server URL in Settings."
        case .unauthorized:
            return "Unauthorized. Please check your API key in Settings."
        case .serverError(let code):
            return "Server error \(code). Please try again later."
        case .networkUnavailable:
            return "Network unavailable. Changes will sync when connectivity is restored."
        case .decodingError(let underlying):
            return "Failed to decode server response: \(underlying.localizedDescription)"
        }
    }
}
