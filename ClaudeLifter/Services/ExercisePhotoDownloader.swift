import Foundation

/// Fetches exercise photos that live in blob storage into the local cache
/// that the exercise screens already read (#170).
///
/// `Exercise.photoURL` holds one of two things:
/// - a LOCAL relative path for a photo taken on this phone
///   (`exercise_photos/{uuid}.jpg`, `LocalPhotoStorage`), or
/// - a BLOB path set through the inbox by the MCP
///   (`exercises/ext/{externalId}.jpg`).
///
/// Before #170 nothing downloaded exercise photos — every one was local. The
/// views load both kinds through `LocalPhotoStorage.loadImage(relativePath:)`,
/// which resolves against Documents; so caching a blob at `Documents/{blobPath}`
/// makes it display with no view change. Downloads go through the existing
/// `ImageUploadServiceProtocol.downloadPhoto(path:)` (a download SAS from
/// `GET /api/images/sas?mode=download`), the same code any exercise photo uses.
@MainActor
protocol ExercisePhotoFetching: AnyObject {
    /// Downloads every blob-path photo that is not cached yet. Never throws:
    /// a photo that fails waits for the next sync. Returns how many landed.
    @discardableResult
    func fetchMissing() async -> Int
}

/// Where downloaded photos are kept. Production is Documents, mirroring the
/// blob path, which is exactly where `LocalPhotoStorage` looks.
@MainActor
protocol ExercisePhotoCaching {
    func hasPhoto(at relativePath: String) -> Bool
    func store(_ data: Data, at relativePath: String) throws
}

@MainActor
struct DocumentsExercisePhotoCache: ExercisePhotoCaching {
    func hasPhoto(at relativePath: String) -> Bool {
        guard let url = LocalPhotoStorage.resolveURL(relativePath: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func store(_ data: Data, at relativePath: String) throws {
        guard let url = LocalPhotoStorage.resolveURL(relativePath: relativePath) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
final class ExercisePhotoDownloader: ExercisePhotoFetching {
    private let exerciseRepository: any ExerciseRepository
    private let imageService: any ImageUploadServiceProtocol
    private let cache: any ExercisePhotoCaching

    init(
        exerciseRepository: any ExerciseRepository,
        imageService: any ImageUploadServiceProtocol,
        cache: any ExercisePhotoCaching = DocumentsExercisePhotoCache()
    ) {
        self.exerciseRepository = exerciseRepository
        self.imageService = imageService
        self.cache = cache
    }

    /// A blob path this downloader may fetch and write under Documents: the
    /// `exercises/` family, a `.jpg`, relative, and with no `..` segment — the
    /// path doubles as a local file path, so it must not escape the cache.
    nonisolated static func isDownloadablePath(_ path: String) -> Bool {
        guard path.hasPrefix("exercises/"), path.hasSuffix(".jpg") else { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        return !segments.contains { $0.isEmpty || $0 == ".." || $0 == "." }
    }

    @discardableResult
    func fetchMissing() async -> Int {
        guard let exercises = try? await exerciseRepository.fetchAll() else { return 0 }
        let paths = Set(exercises.compactMap(\.photoURL))
            .filter { Self.isDownloadablePath($0) && !cache.hasPhoto(at: $0) }
        var fetched = 0
        for path in paths.sorted() {
            guard let data = try? await imageService.downloadPhoto(path: path),
                  !data.isEmpty else { continue }
            do {
                try cache.store(data, at: path)
                fetched += 1
            } catch {
                continue
            }
        }
        return fetched
    }
}
