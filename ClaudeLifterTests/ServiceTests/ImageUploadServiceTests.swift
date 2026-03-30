import Testing
import Foundation
@testable import ClaudeLifter

@Suite("ImageUploadService Tests")
struct ImageUploadServiceTests {

    // MARK: - Helpers

    private func makeService() -> (ImageUploadService, MockNetworkService) {
        let network = MockNetworkService()
        let service = ImageUploadService(networkService: network)
        return (service, network)
    }

    private func makeSASResponse(exerciseId: UUID) -> SASResponse {
        SASResponse(
            sasUrl: "https://stworkout.blob.core.windows.net/workout-images/exercises/\(exerciseId).jpg?sv=sas",
            blobUrl: "https://stworkout.blob.core.windows.net/workout-images/exercises/\(exerciseId).jpg"
        )
    }

    private func makeFakeImageData() -> Data {
        // Minimal 1x1 JPEG
        return Data([
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
            0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
            0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
            0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
            0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
            0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
            0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
            0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
            0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
            0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
            0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
            0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xFB, 0x26,
            0xA5, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xD9
        ])
    }

    // MARK: - uploadPhoto

    @Test("uploadPhoto requests SAS URL with correct path and mode")
    func uploadPhotoRequestsSASWithCorrectPath() async throws {
        let (service, network) = makeService()
        let exerciseId = UUID()
        let sasResponse = makeSASResponse(exerciseId: exerciseId)
        network.setResponse(sasResponse, forEndpoint: "/api/images/sas")

        _ = try? await service.uploadPhoto(exerciseId: exerciseId, imageData: makeFakeImageData())

        let expectedPath = "exercises/\(exerciseId.uuidString).jpg"
        #expect(network.lastQueryItems?.contains(where: { $0.name == "path" && $0.value == expectedPath }) == true)
        #expect(network.lastQueryItems?.contains(where: { $0.name == "mode" && $0.value == "upload" }) == true)
    }

    @Test("uploadPhoto returns blob URL on success")
    func uploadPhotoReturnsBlobURL() async throws {
        let (service, network) = makeService()
        let exerciseId = UUID()
        let sasResponse = makeSASResponse(exerciseId: exerciseId)
        network.setResponse(sasResponse, forEndpoint: "/api/images/sas")

        let result = try await service.uploadPhoto(exerciseId: exerciseId, imageData: makeFakeImageData())

        #expect(result == sasResponse.blobUrl)
    }

    @Test("uploadPhoto calls uploadBlob with SAS URL")
    func uploadPhotoCallsUploadBlob() async throws {
        let (service, network) = makeService()
        let exerciseId = UUID()
        let sasResponse = makeSASResponse(exerciseId: exerciseId)
        network.setResponse(sasResponse, forEndpoint: "/api/images/sas")

        _ = try? await service.uploadPhoto(exerciseId: exerciseId, imageData: makeFakeImageData())

        #expect(network.uploadBlobCallCount == 1)
    }

    @Test("uploadPhoto propagates network errors")
    func uploadPhotoNetworkError() async {
        let (service, network) = makeService()
        network.errorToThrow = NSError(domain: "test", code: 500, userInfo: [NSLocalizedDescriptionKey: "server error"])

        do {
            _ = try await service.uploadPhoto(exerciseId: UUID(), imageData: makeFakeImageData())
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error.localizedDescription == "server error")
        }
    }

    // MARK: - downloadPhoto

    @Test("downloadPhoto requests SAS URL with download mode")
    func downloadPhotoRequestsDownloadSAS() async throws {
        let (service, network) = makeService()
        let path = "exercises/some-id.jpg"
        let exerciseId = UUID()
        let sasResponse = makeSASResponse(exerciseId: exerciseId)
        network.setResponse(sasResponse, forEndpoint: "/api/images/sas")
        network.downloadBlobResult = Data([1, 2, 3])

        _ = try? await service.downloadPhoto(path: path)

        #expect(network.lastQueryItems?.contains(where: { $0.name == "path" && $0.value == path }) == true)
        #expect(network.lastQueryItems?.contains(where: { $0.name == "mode" && $0.value == "download" }) == true)
    }

    @Test("downloadPhoto returns data from blob storage")
    func downloadPhotoReturnsData() async throws {
        let (service, network) = makeService()
        let exerciseId = UUID()
        let sasResponse = makeSASResponse(exerciseId: exerciseId)
        network.setResponse(sasResponse, forEndpoint: "/api/images/sas")
        let expected = Data([0xDE, 0xAD, 0xBE, 0xEF])
        network.downloadBlobResult = expected

        let result = try await service.downloadPhoto(path: "exercises/test.jpg")

        #expect(result == expected)
    }

    @Test("downloadPhoto propagates download errors")
    func downloadPhotoError() async {
        let (service, network) = makeService()
        network.errorToThrow = NSError(domain: "test", code: 404, userInfo: [NSLocalizedDescriptionKey: "not found"])

        do {
            _ = try await service.downloadPhoto(path: "exercises/missing.jpg")
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error.localizedDescription == "not found")
        }
    }
}
