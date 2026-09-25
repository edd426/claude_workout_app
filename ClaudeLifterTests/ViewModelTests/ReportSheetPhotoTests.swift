import Foundation
import SwiftData
import Testing
import UIKit
@testable import ClaudeLifter

/// Issue #141, the sheet half: attach a photo while filing, keep it on the
/// phone, and never let the photo stop the report from being filed.
@Suite("Report sheet photos (#141)")
@MainActor
struct ReportSheetPhotoTests {

    private struct Env {
        let container: ModelContainer
        let repository: SwiftDataExerciseReportRepository
        let store: MockReportPhotoStore
        let vm: ReportSheetViewModel

        @MainActor
        init() throws {
            container = try makeTestContainer()
            repository = SwiftDataExerciseReportRepository(context: container.mainContext)
            store = MockReportPhotoStore()
            vm = ReportSheetViewModel(
                context: ReportContext(
                    exerciseExternalId: "Machine_Triceps_Extension",
                    exerciseName: "Machine Triceps Extension"
                ),
                repository: repository,
                photoStore: store
            )
            vm.detail = "Is this the machine in the description?"
        }
    }

    private func makeImageData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 40, height: 30),
            format: format
        ).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        return image.pngData() ?? Data()
    }

    @Test("attaching a photo keeps it as JPEG, ready to file")
    func attachKeepsJPEG() throws {
        let env = try Env()

        let attached = env.vm.attachPhoto(makeImageData())

        #expect(attached)
        let data = try #require(env.vm.photoData)
        #expect(data.starts(with: [0xFF, 0xD8]))
        #expect(env.vm.photoError == nil)
    }

    @Test("data that is not an image is refused with a message")
    func attachRefusesNonImage() throws {
        let env = try Env()

        let attached = env.vm.attachPhoto(Data("nope".utf8))

        #expect(!attached)
        #expect(env.vm.photoData == nil)
        #expect(env.vm.photoError != nil)
    }

    @Test("removing the photo clears it")
    func removeClears() throws {
        let env = try Env()
        env.vm.attachPhoto(makeImageData())

        env.vm.removePhoto()

        #expect(env.vm.photoData == nil)
    }

    @Test("filing with a photo stores it under the report's id")
    func submitStoresPhotoByReportId() async throws {
        let env = try Env()
        env.vm.attachPhoto(makeImageData())

        let saved = await env.vm.submit()

        #expect(saved)
        let report = try #require(try await env.repository.fetchAll().first)
        #expect(env.store.photos[report.id] != nil)
        // Not uploaded yet: photoURL is only set once the blob exists.
        #expect(report.photoURL == nil)
    }

    @Test("filing without a photo stores nothing")
    func submitWithoutPhoto() async throws {
        let env = try Env()

        let saved = await env.vm.submit()

        #expect(saved)
        #expect(env.store.saveCallCount == 0)
    }

    @Test("a photo that cannot be written still files the report")
    func photoFailureNeverBlocksReport() async throws {
        let env = try Env()
        env.vm.attachPhoto(makeImageData())
        env.store.saveError = CocoaError(.fileWriteOutOfSpace)

        let saved = await env.vm.submit()

        #expect(saved, "The report is the point; the photo is a bonus")
        #expect(try await env.repository.fetchAll().count == 1)
    }
}
