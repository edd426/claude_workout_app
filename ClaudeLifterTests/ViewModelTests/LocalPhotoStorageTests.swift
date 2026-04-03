import Testing
import Foundation
import UIKit
@testable import ClaudeLifter

@Suite("LocalPhotoStorage Tests")
struct LocalPhotoStorageTests {

    // MARK: - Helpers

    private func makeJPEGData(color: UIColor = .red, size: CGSize = CGSize(width: 10, height: 10)) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    private func cleanupPhoto(exerciseId: UUID) {
        let relativePath = "exercise_photos/\(exerciseId.uuidString).jpg"
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsURL.appendingPathComponent(relativePath)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - savePhoto tests

    @Test("savePhoto returns relative path string")
    func savePhotoReturnsRelativePath() throws {
        let exerciseId = UUID()
        let data = makeJPEGData()
        defer { cleanupPhoto(exerciseId: exerciseId) }

        let path = try LocalPhotoStorage.savePhoto(data: data, exerciseId: exerciseId)

        #expect(path == "exercise_photos/\(exerciseId.uuidString).jpg")
    }

    @Test("savePhoto creates file at expected location")
    func savePhotoCreatesFile() throws {
        let exerciseId = UUID()
        let data = makeJPEGData()
        defer { cleanupPhoto(exerciseId: exerciseId) }

        let path = try LocalPhotoStorage.savePhoto(data: data, exerciseId: exerciseId)

        let docsURL = try #require(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let fileURL = docsURL.appendingPathComponent(path)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("savePhoto creates exercise_photos directory if it does not exist")
    func savePhotoCreatesDirectory() throws {
        let exerciseId = UUID()
        let data = makeJPEGData()
        defer { cleanupPhoto(exerciseId: exerciseId) }

        _ = try LocalPhotoStorage.savePhoto(data: data, exerciseId: exerciseId)

        let docsURL = try #require(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let dirURL = docsURL.appendingPathComponent("exercise_photos")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir)
        #expect(exists && isDir.boolValue)
    }

    @Test("savePhoto overwrites existing photo for same exercise")
    func savePhotoOverwritesExisting() throws {
        let exerciseId = UUID()
        let firstData = makeJPEGData(color: .red)
        let secondData = makeJPEGData(color: .blue)
        defer { cleanupPhoto(exerciseId: exerciseId) }

        _ = try LocalPhotoStorage.savePhoto(data: firstData, exerciseId: exerciseId)
        let path = try LocalPhotoStorage.savePhoto(data: secondData, exerciseId: exerciseId)

        let docsURL = try #require(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let fileURL = docsURL.appendingPathComponent(path)
        let savedData = try Data(contentsOf: fileURL)
        #expect(savedData == secondData)
    }

    // MARK: - resolveURL tests

    @Test("resolveURL returns nil for nil input")
    func resolveURLReturnsNilForNilInput() {
        let result = LocalPhotoStorage.resolveURL(relativePath: nil)
        #expect(result == nil)
    }

    @Test("resolveURL returns nil for empty string")
    func resolveURLReturnsNilForEmptyString() {
        let result = LocalPhotoStorage.resolveURL(relativePath: "")
        #expect(result == nil)
    }

    @Test("resolveURL constructs absolute URL from relative path")
    func resolveURLConstructsAbsoluteURL() throws {
        let exerciseId = UUID()
        let relativePath = "exercise_photos/\(exerciseId.uuidString).jpg"

        let result = try #require(LocalPhotoStorage.resolveURL(relativePath: relativePath))

        let docsURL = try #require(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let expected = docsURL.appendingPathComponent(relativePath)
        #expect(result == expected)
    }

    @Test("resolveURL round-trips with savePhoto")
    func resolveURLRoundTripsWithSavePhoto() throws {
        let exerciseId = UUID()
        let data = makeJPEGData()
        defer { cleanupPhoto(exerciseId: exerciseId) }

        let relativePath = try LocalPhotoStorage.savePhoto(data: data, exerciseId: exerciseId)
        let resolvedURL = try #require(LocalPhotoStorage.resolveURL(relativePath: relativePath))

        #expect(FileManager.default.fileExists(atPath: resolvedURL.path))
        let loadedData = try Data(contentsOf: resolvedURL)
        #expect(loadedData == data)
    }

    // MARK: - loadImage tests

    @Test("loadImage returns nil when file does not exist")
    func loadImageReturnsNilWhenFileAbsent() {
        let nonExistentPath = "exercise_photos/nonexistent-\(UUID().uuidString).jpg"
        let result = LocalPhotoStorage.loadImage(relativePath: nonExistentPath)
        #expect(result == nil)
    }

    @Test("loadImage returns nil for nil path")
    func loadImageReturnsNilForNilPath() {
        let result = LocalPhotoStorage.loadImage(relativePath: nil)
        #expect(result == nil)
    }

    @Test("loadImage returns UIImage after savePhoto")
    func loadImageReturnsSavedImage() throws {
        let exerciseId = UUID()
        let data = makeJPEGData()
        defer { cleanupPhoto(exerciseId: exerciseId) }

        let relativePath = try LocalPhotoStorage.savePhoto(data: data, exerciseId: exerciseId)
        let image = LocalPhotoStorage.loadImage(relativePath: relativePath)

        #expect(image != nil)
    }
}
