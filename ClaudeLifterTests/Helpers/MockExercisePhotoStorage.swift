import Foundation
@testable import ClaudeLifter

@MainActor
final class MockExercisePhotoStorage: ExercisePhotoStorage {
    var savedPath = "exercise_photos/saved.jpg"
    var errorToThrow: Error?
    var saveCallCount = 0
    var lastExerciseId: UUID?

    func savePhoto(data: Data, exerciseId: UUID) throws -> String {
        saveCallCount += 1
        lastExerciseId = exerciseId
        if let errorToThrow {
            throw errorToThrow
        }
        return savedPath
    }
}
