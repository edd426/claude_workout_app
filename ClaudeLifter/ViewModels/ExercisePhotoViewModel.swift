import Foundation
import Observation
import UIKit

@MainActor
protocol ExercisePhotoStorage {
    func savePhoto(data: Data, exerciseId: UUID) throws -> String
}

@MainActor
struct LocalExercisePhotoStorage: ExercisePhotoStorage {
    func savePhoto(data: Data, exerciseId: UUID) throws -> String {
        try LocalPhotoStorage.savePhoto(data: data, exerciseId: exerciseId)
    }
}

@Observable
@MainActor
final class ExercisePhotoViewModel {
    var photoURL: String?
    var isSaving = false
    var errorMessage: String?

    private let storage: any ExercisePhotoStorage

    init(
        photoURL: String? = nil,
        storage: any ExercisePhotoStorage = LocalExercisePhotoStorage()
    ) {
        self.photoURL = photoURL
        self.storage = storage
    }

    @discardableResult
    func attachPhoto(
        to exercise: Exercise,
        loadData: () async throws -> Data?
    ) async -> Bool {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let data: Data
        do {
            guard let loadedData = try await loadData() else {
                errorMessage = "Could not load the selected photo. Try choosing it again."
                return false
            }
            data = loadedData
        } catch {
            errorMessage = "Could not load the selected photo. Try choosing it again."
            return false
        }

        guard let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Could not use the selected photo. Try choosing another image."
            return false
        }

        do {
            let path = try storage.savePhoto(data: jpegData, exerciseId: exercise.id)
            photoURL = path
            exercise.photoURL = path
            return true
        } catch {
            errorMessage = "Could not attach the photo. Try selecting it again."
            return false
        }
    }
}
