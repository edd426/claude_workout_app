import Foundation

protocol ImageUploadServiceProtocol: Sendable {
    func uploadPhoto(exerciseId: UUID, imageData: Data) async throws -> String
    /// Uploads an already-encoded JPEG to `reports/{reportId}.jpg` and returns
    /// that blob path — the value `ExerciseReport.photoURL` then holds (#141).
    func uploadReportPhoto(reportId: UUID, jpegData: Data) async throws -> String
    func downloadPhoto(path: String) async throws -> Data?
}

/// `GET /api/images/sas` — `SasResponse` in infra/functions/src/shared/types.ts.
struct SASResponse: Decodable, Sendable {
    let sasUrl: String
    let expiresAt: String?

    /// The blob's own URL: the SAS URL without its token. This used to be a
    /// decoded `blobUrl` field, which the server has never sent — so every
    /// real decode of this type failed. Nothing called the upload path until
    /// #141, which is why it went unnoticed.
    var blobUrl: String {
        guard var components = URLComponents(string: sasUrl) else { return sasUrl }
        components.query = nil
        return components.string ?? sasUrl
    }
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
