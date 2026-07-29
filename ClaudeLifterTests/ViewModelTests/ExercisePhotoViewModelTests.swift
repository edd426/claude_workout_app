import Foundation
import Testing
import UIKit
@testable import ClaudeLifter

@Suite("ExercisePhotoViewModel Tests")
@MainActor
struct ExercisePhotoViewModelTests {
    @Test("failed photo load reports the failure and keeps the current photo")
    func failedPhotoLoadKeepsCurrentPhoto() async {
        let storage = MockExercisePhotoStorage()
        let exercise = Exercise(name: "Chest Press", photoURL: "exercise_photos/current.jpg")
        let vm = ExercisePhotoViewModel(
            photoURL: exercise.photoURL,
            storage: storage
        )

        let attached = await vm.attachPhoto(to: exercise) {
            throw NSError(domain: "test", code: 1)
        }

        #expect(attached == false)
        #expect(vm.photoURL == "exercise_photos/current.jpg")
        #expect(exercise.photoURL == "exercise_photos/current.jpg")
        #expect(storage.saveCallCount == 0)
        #expect(vm.errorMessage == "Could not load the selected photo. Try choosing it again.")
    }

    @Test("failed photo save reports the failure and keeps the current photo")
    func failedPhotoSaveKeepsCurrentPhoto() async {
        let storage = MockExercisePhotoStorage()
        storage.errorToThrow = NSError(domain: "test", code: 2)
        let exercise = Exercise(name: "Chest Press", photoURL: "exercise_photos/current.jpg")
        let vm = ExercisePhotoViewModel(
            photoURL: exercise.photoURL,
            storage: storage
        )

        let attached = await vm.attachPhoto(to: exercise) {
            makeJPEGData()
        }

        #expect(attached == false)
        #expect(vm.photoURL == "exercise_photos/current.jpg")
        #expect(exercise.photoURL == "exercise_photos/current.jpg")
        #expect(storage.saveCallCount == 1)
        #expect(vm.errorMessage == "Could not attach the photo. Try selecting it again.")
    }

    private func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 10, height: 10)))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}
