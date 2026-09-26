import Testing
import Foundation
import SwiftData
import UIKit
@testable import ClaudeLifter

/// Issue #141 — a photo on an exercise report. "It's easier to show you what's
/// wrong as an image." The gym is often offline, so the photo is kept on the
/// phone and uploaded on a later sync; a report never waits for it.
@Suite("Report photos (#141)")
@MainActor
struct ReportPhotoTests {

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("report-photos-\(UUID().uuidString)")
    }

    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        // Scale 1 so the size is in pixels: a 3x renderer would make a
        // 9000-pixel image and blur what "no larger than 1024" means.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.pngData() ?? Data()
    }

    // MARK: - Path contract

    @Test("the blob path is reports/{reportId}.jpg")
    func blobPathContract() {
        let id = UUID()
        // infra/mcp get_report_photo accepts exactly this and nothing else.
        #expect(ReportPhotoPath.blobPath(for: id) == "reports/\(id.uuidString).jpg")
    }

    // MARK: - Encoding

    @Test("a photo is re-encoded as JPEG no larger than 1024 on its long edge")
    func encodingDownscalesToJPEG() throws {
        let png = makeImageData(width: 3000, height: 1500)

        let jpeg = try #require(JPEGEncoding.jpeg(from: png))

        #expect(jpeg.starts(with: [0xFF, 0xD8]), "The MCP tool refuses anything but JPEG")
        let image = try #require(UIImage(data: jpeg))
        let longEdge = max(image.size.width * image.scale, image.size.height * image.scale)
        #expect(longEdge <= 1024)
    }

    @Test("data that is not an image is refused rather than uploaded as-is")
    func encodingRefusesNonImages() {
        #expect(JPEGEncoding.jpeg(from: Data("not an image".utf8)) == nil)
    }

    // MARK: - Local store

    @Test("a saved photo reads back by report id")
    func storeRoundTrip() throws {
        let store = LocalReportPhotoStore(directory: makeTempDirectory())
        let id = UUID()
        let bytes = Data([0xFF, 0xD8, 0x01, 0x02])

        try store.save(bytes, reportId: id)

        #expect(store.data(for: id) == bytes)
        #expect(store.data(for: UUID()) == nil)
    }

    @Test("delete removes the photo")
    func storeDelete() throws {
        let store = LocalReportPhotoStore(directory: makeTempDirectory())
        let id = UUID()
        try store.save(Data([0xFF, 0xD8]), reportId: id)

        store.delete(reportId: id)

        #expect(store.data(for: id) == nil)
    }

    // MARK: - Uploader

    private struct UploaderEnv {
        let container: ModelContainer
        let repository: SwiftDataExerciseReportRepository
        let store: MockReportPhotoStore
        let upload: MockImageUploadService
        let uploader: ReportPhotoUploader

        @MainActor
        init() throws {
            container = try makeTestContainer()
            repository = SwiftDataExerciseReportRepository(context: container.mainContext)
            store = MockReportPhotoStore()
            upload = MockImageUploadService()
            uploader = ReportPhotoUploader(
                reportRepository: repository,
                photoStore: store,
                imageUploadService: upload
            )
        }

        @MainActor
        func addReport(photoURL: String? = nil, syncStatus: SyncStatus = .synced) async throws -> ExerciseReport {
            let report = ExerciseReport(
                category: .wrongExercise,
                detail: "Not the machine I have",
                photoURL: photoURL,
                syncStatus: syncStatus
            )
            try await repository.save(report)
            return report
        }
    }

    @Test("a waiting photo is uploaded and the report then points at it")
    func uploadsWaitingPhoto() async throws {
        let env = try UploaderEnv()
        let report = try await env.addReport()
        env.store.photos[report.id] = Data([0xFF, 0xD8, 0xFF])

        let uploaded = await env.uploader.uploadPending()

        #expect(uploaded == 1)
        #expect(env.upload.uploadedReportIds == [report.id])
        #expect(report.photoURL == "reports/\(report.id.uuidString).jpg")
        #expect(report.syncStatus == .pending, "The new photoURL has to reach the mirror")
    }

    @Test("a report that already points at its photo is not uploaded again")
    func skipsUploadedPhotos() async throws {
        let env = try UploaderEnv()
        let report = try await env.addReport(photoURL: "reports/X.jpg")
        env.store.photos[report.id] = Data([0xFF, 0xD8, 0xFF])

        let uploaded = await env.uploader.uploadPending()

        #expect(uploaded == 0)
        #expect(env.upload.uploadedReportIds.isEmpty)
    }

    @Test("a report with no photo on the phone is skipped")
    func skipsReportsWithoutPhotos() async throws {
        let env = try UploaderEnv()
        _ = try await env.addReport()

        let uploaded = await env.uploader.uploadPending()

        #expect(uploaded == 0)
        #expect(env.upload.uploadedReportIds.isEmpty)
    }

    @Test("a failed upload leaves photoURL empty so the next sync retries")
    func failedUploadRetriesLater() async throws {
        let env = try UploaderEnv()
        let report = try await env.addReport()
        env.store.photos[report.id] = Data([0xFF, 0xD8, 0xFF])
        // What an undeployed Functions app answers for a reports/ path.
        env.upload.reportUploadError = SyncError.serverError(400)

        let uploaded = await env.uploader.uploadPending()

        #expect(uploaded == 0)
        #expect(report.photoURL == nil, "photoURL means the blob exists — never set it early")
        #expect(report.syncStatus == .synced)

        env.upload.reportUploadError = nil
        #expect(await env.uploader.uploadPending() == 1)
        #expect(report.photoURL != nil)
    }

    // MARK: - Sync

    @Test("sync uploads waiting photos before it decides whether to push")
    func syncUploadsThenPushesPhotoURL() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let exerciseRepo = SwiftDataExerciseRepository(context: context)
        let bodyWeightRepo = SwiftDataBodyWeightRepository(context: context)
        let reportRepo = SwiftDataExerciseReportRepository(context: context)
        let network = MockNetworkService()
        network.pushSnapshotResult = SnapshotPushResponse(
            revision: 1,
            serverTime: Date(timeIntervalSinceReferenceDate: 800_000_000),
            counts: [:]
        )
        let settings = SettingsManager(
            defaults: UserDefaults(suiteName: "report-photo-sync-\(UUID())")!
        )
        settings.serverURL = "https://example.com"
        let store = MockReportPhotoStore()
        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            exerciseRepository: exerciseRepo,
            bodyWeightRepository: bodyWeightRepo,
            exerciseReportRepository: reportRepo,
            networkService: network,
            settings: settings,
            inboxApplier: InboxApplier(
                templateRepository: templateRepo,
                exerciseRepository: exerciseRepo,
                reportRepository: reportRepo
            ),
            reportPhotoUploader: ReportPhotoUploader(
                reportRepository: reportRepo,
                photoStore: store,
                imageUploadService: MockImageUploadService()
            )
        )
        // Filed and synced offline at the gym; only the photo is left.
        let report = ExerciseReport(
            category: .wrongExercise,
            detail: "Not the machine I have",
            syncStatus: .synced
        )
        try await reportRepo.save(report)
        store.photos[report.id] = Data([0xFF, 0xD8, 0xFF])

        await manager.syncIfNeeded()

        #expect(network.pushSnapshotCallCount == 1)
        let pushed = try #require(network.lastSnapshotRequest?.snapshot.exerciseReports.first)
        #expect(pushed.photoURL == "reports/\(report.id.uuidString).jpg")
        withExtendedLifetime(container) {}
    }
}
