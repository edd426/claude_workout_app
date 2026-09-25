import Foundation
import UIKit

// Issue #141 — a photo on an exercise report ("it's easier to show you what's
// wrong as an image"). The flow, and why it is shaped this way:
//
// 1. The report sheet re-encodes the photo as a ≤1024px JPEG and keeps it on
//    the phone under the report's id. The gym is where connectivity is worst,
//    so filing never touches the network and never waits for the image.
// 2. On a later sync, `ReportPhotoUploader` uploads each kept photo that the
//    report does not yet point at, to blob `reports/{reportId}.jpg`, and only
//    THEN sets `photoURL` to that path. `photoURL` non-nil therefore means the
//    blob exists, which is what the MCP tool `get_report_photo` relies on.
// 3. The changed report reaches the mirror in the same sync's snapshot push.

/// Where a report's photo lives in blob storage, and the exact value
/// `ExerciseReport.photoURL` holds once it is uploaded. The Functions SAS
/// endpoint and `get_report_photo` accept this shape and nothing else.
enum ReportPhotoPath {
    static func blobPath(for reportId: UUID) -> String {
        "reports/\(reportId.uuidString).jpg"
    }
}

/// Re-encodes image data as a downscaled JPEG.
enum JPEGEncoding {
    /// Long edge, in pixels. A phone photo is ~4000px; 1024 still shows which
    /// machine it is, at roughly a tenth of the bytes.
    static let maxDimension: CGFloat = 1024
    static let quality: CGFloat = 0.8

    /// Nil when `data` is not an image. Never passes bytes through unencoded:
    /// the MCP tool refuses anything that is not a JPEG, and a HEIC from the
    /// photo library would otherwise upload under a `.jpg` name.
    static func jpeg(
        from data: Data,
        maxDimension: CGFloat = JPEGEncoding.maxDimension,
        quality: CGFloat = JPEGEncoding.quality
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > 0 else { return nil }
        let factor = min(1, maxDimension / longEdge)
        let target = CGSize(
            width: (pixelWidth * factor).rounded(),
            height: (pixelHeight * factor).rounded()
        )
        // Scale 1, so `target` is pixels. The renderer's default is the
        // screen scale, which would triple the output on every axis.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// Report photos kept on the phone, keyed by report id.
@MainActor
protocol ReportPhotoStoring {
    func save(_ jpegData: Data, reportId: UUID) throws
    func data(for reportId: UUID) -> Data?
    func delete(reportId: UUID)
}

/// `<Documents>/report_photos/<reportId>.jpg`. Kept after upload so the phone
/// can show the photo without downloading it back.
@MainActor
struct LocalReportPhotoStore: ReportPhotoStoring {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    private static var defaultDirectory: URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("report_photos", isDirectory: true)
    }

    private func fileURL(for reportId: UUID) -> URL {
        directory.appendingPathComponent("\(reportId.uuidString).jpg")
    }

    func save(_ jpegData: Data, reportId: UUID) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try jpegData.write(to: fileURL(for: reportId), options: .atomic)
    }

    func data(for reportId: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: reportId))
    }

    func delete(reportId: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: reportId))
    }
}

@MainActor
protocol ReportPhotoUploading {
    /// Uploads every kept photo whose report does not point at it yet, and
    /// returns how many it uploaded. Never throws: a photo that fails is
    /// simply still waiting on the next sync.
    @discardableResult
    func uploadPending() async -> Int
}

@MainActor
final class ReportPhotoUploader: ReportPhotoUploading {
    private let reportRepository: any ExerciseReportRepository
    private let photoStore: any ReportPhotoStoring
    private let imageUploadService: any ImageUploadServiceProtocol

    /// The most recent upload failure, for diagnostics. Uploads are retried on
    /// every sync, so a failure is a delay, not a loss.
    private(set) var lastError: Error?

    init(
        reportRepository: any ExerciseReportRepository,
        photoStore: any ReportPhotoStoring,
        imageUploadService: any ImageUploadServiceProtocol
    ) {
        self.reportRepository = reportRepository
        self.photoStore = photoStore
        self.imageUploadService = imageUploadService
    }

    @discardableResult
    func uploadPending() async -> Int {
        let reports: [ExerciseReport]
        do {
            reports = try await reportRepository.fetchAll()
        } catch {
            lastError = error
            return 0
        }

        var uploaded = 0
        for report in reports where report.photoURL == nil {
            guard let jpegData = photoStore.data(for: report.id) else { continue }
            do {
                let path = try await imageUploadService.uploadReportPhoto(
                    reportId: report.id,
                    jpegData: jpegData
                )
                report.photoURL = path
                report.recordChange()
                try await reportRepository.save(report)
                uploaded += 1
            } catch {
                // Most likely offline, or a Functions app deployed before
                // #141 refusing the reports/ path with a 400. photoURL stays
                // nil, so the next sync tries again.
                lastError = error
            }
        }
        return uploaded
    }
}
