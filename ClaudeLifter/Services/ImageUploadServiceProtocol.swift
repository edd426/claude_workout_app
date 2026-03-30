import Foundation

protocol ImageUploadServiceProtocol: Sendable {
    func uploadPhoto(exerciseId: UUID, imageData: Data) async throws -> String
    func downloadPhoto(path: String) async throws -> Data?
}

struct SASResponse: Decodable, Sendable {
    let sasUrl: String
    let blobUrl: String
}

enum ImageUploadError: Error, LocalizedError {
    case invalidSASResponse
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidSASResponse: return "Failed to get image upload URL from server."
        case .compressionFailed: return "Failed to compress image for upload."
        }
    }
}
