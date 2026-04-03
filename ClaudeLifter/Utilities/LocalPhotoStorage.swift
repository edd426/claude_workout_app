import UIKit

/// Saves and loads exercise photos from the app's local documents directory.
/// Photos are stored at `exercise_photos/{exerciseId}.jpg` relative to the documents root.
/// The relative path is stored in `Exercise.photoURL` so it remains valid across app reinstalls
/// that preserve the documents directory.
enum LocalPhotoStorage {

    private static let subdirectory = "exercise_photos"

    // MARK: - Save

    /// Compresses `data` as JPEG (quality 0.8) and saves it to
    /// `<Documents>/exercise_photos/<exerciseId>.jpg`.
    /// - Returns: The relative path string suitable for storage in `Exercise.photoURL`.
    @discardableResult
    static func savePhoto(data: Data, exerciseId: UUID) throws -> String {
        let relativePath = "\(subdirectory)/\(exerciseId.uuidString).jpg"
        let docsURL = try documentsURL()
        let dirURL = docsURL.appendingPathComponent(subdirectory)

        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        let fileURL = docsURL.appendingPathComponent(relativePath)
        try data.write(to: fileURL, options: .atomic)
        return relativePath
    }

    // MARK: - Resolve

    /// Converts a relative path (e.g. `"exercise_photos/<id>.jpg"`) to an absolute `URL`.
    /// Returns `nil` for `nil` or empty input.
    static func resolveURL(relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        guard let docsURL = try? documentsURL() else { return nil }
        return docsURL.appendingPathComponent(relativePath)
    }

    // MARK: - Load

    /// Loads a `UIImage` from a relative path previously returned by `savePhoto`.
    /// Returns `nil` if the path is nil/empty or the file does not exist.
    static func loadImage(relativePath: String?) -> UIImage? {
        guard let url = resolveURL(relativePath: relativePath) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Private

    private static func documentsURL() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LocalPhotoStorageError.documentsDirectoryUnavailable
        }
        return url
    }
}

enum LocalPhotoStorageError: Error, LocalizedError {
    case documentsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "Could not locate the app's documents directory."
        }
    }
}
