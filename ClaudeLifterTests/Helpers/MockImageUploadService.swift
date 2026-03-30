import Foundation
@testable import ClaudeLifter

final class MockImageUploadService: ImageUploadServiceProtocol, @unchecked Sendable {
    var uploadCallCount = 0
    var downloadCallCount = 0
    var lastUploadedExerciseId: UUID? = nil
    var lastUploadedData: Data? = nil
    var lastDownloadedPath: String? = nil
    var uploadResultURL = "https://stworkout.blob.core.windows.net/workout-images/exercises/test.jpg"
    var downloadResultData: Data? = nil
    var errorToThrow: Error? = nil

    func uploadPhoto(exerciseId: UUID, imageData: Data) async throws -> String {
        uploadCallCount += 1
        lastUploadedExerciseId = exerciseId
        lastUploadedData = imageData
        if let error = errorToThrow { throw error }
        return uploadResultURL
    }

    func downloadPhoto(path: String) async throws -> Data? {
        downloadCallCount += 1
        lastDownloadedPath = path
        if let error = errorToThrow { throw error }
        return downloadResultData
    }
}
