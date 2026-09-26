import Foundation
@testable import ClaudeLifter

/// In-memory `ReportPhotoStoring` (#141).
@MainActor
final class MockReportPhotoStore: ReportPhotoStoring {
    var photos: [UUID: Data] = [:]
    var saveError: Error? = nil
    var saveCallCount = 0

    func save(_ jpegData: Data, reportId: UUID) throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        photos[reportId] = jpegData
    }

    func data(for reportId: UUID) -> Data? {
        photos[reportId]
    }

    func delete(reportId: UUID) {
        photos[reportId] = nil
    }
}
