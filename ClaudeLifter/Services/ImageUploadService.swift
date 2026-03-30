import Foundation
import UIKit

final class ImageUploadService: ImageUploadServiceProtocol {
    private let networkService: any NetworkServiceProtocol
    private let maxDimension: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.8

    init(networkService: any NetworkServiceProtocol) {
        self.networkService = networkService
    }

    func uploadPhoto(exerciseId: UUID, imageData: Data) async throws -> String {
        guard let compressed = compress(imageData: imageData) else {
            throw ImageUploadError.compressionFailed
        }

        let path = "exercises/\(exerciseId.uuidString).jpg"
        let items = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "mode", value: "upload")]
        let sasResponse: SASResponse = try await networkService.get(endpoint: "/api/images/sas", queryItems: items)

        guard let sasURL = URL(string: sasResponse.sasUrl) else {
            throw ImageUploadError.invalidSASResponse
        }

        try await networkService.uploadBlob(url: sasURL, data: compressed, contentType: "image/jpeg")
        return sasResponse.blobUrl
    }

    func downloadPhoto(path: String) async throws -> Data? {
        let items = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "mode", value: "download")]
        let sasResponse: SASResponse = try await networkService.get(endpoint: "/api/images/sas", queryItems: items)
        guard let sasURL = URL(string: sasResponse.sasUrl) else {
            throw ImageUploadError.invalidSASResponse
        }
        return try await networkService.downloadBlob(url: sasURL)
    }

    private func compress(imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else {
            // If the data cannot be decoded as a UIImage (e.g., already-encoded or
            // minimal binary data), upload as-is rather than failing.
            return imageData
        }
        let resized = resize(image: image)
        return resized.jpegData(compressionQuality: jpegQuality) ?? imageData
    }

    private func resize(image: UIImage) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxDimension else { return image }

        let scale = maxDimension / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
