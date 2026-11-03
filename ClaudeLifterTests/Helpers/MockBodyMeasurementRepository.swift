import Foundation
@testable import ClaudeLifter

/// Array-backed `BodyMeasurementRepository` with error injection.
@MainActor
final class MockBodyMeasurementRepository: BodyMeasurementRepository {
    var measurements: [BodyMeasurement] = []
    var errorToThrow: Error?
    var saveCallCount = 0

    func fetchAll() async throws -> [BodyMeasurement] {
        if let errorToThrow { throw errorToThrow }
        return measurements.sorted { $0.recordedAt > $1.recordedAt }
    }

    func fetch(id: UUID) async throws -> BodyMeasurement? {
        if let errorToThrow { throw errorToThrow }
        return measurements.first { $0.id == id }
    }

    func fetch(site: MeasurementSite) async throws -> [BodyMeasurement] {
        try await fetchAll().filter { $0.siteRaw == site.rawValue }
    }

    func fetch(site: MeasurementSite, from start: Date, to end: Date) async throws -> [BodyMeasurement] {
        try await fetch(site: site)
            .filter { $0.recordedAt >= start && $0.recordedAt <= end }
            .reversed()
    }

    func fetchLatest(site: MeasurementSite) async throws -> BodyMeasurement? {
        try await fetch(site: site).first
    }

    func fetchLatestPerSite() async throws -> [MeasurementSite: BodyMeasurement] {
        var latest: [MeasurementSite: BodyMeasurement] = [:]
        for measurement in try await fetchAll() {
            guard let site = measurement.site, latest[site] == nil else { continue }
            latest[site] = measurement
        }
        return latest
    }

    func fetchPending() async throws -> [BodyMeasurement] {
        try await fetchAll().filter { $0.syncStatus == .pending }
    }

    func save(_ measurement: BodyMeasurement) async throws {
        saveCallCount += 1
        if let errorToThrow { throw errorToThrow }
        if !measurements.contains(where: { $0.id == measurement.id }) {
            measurements.append(measurement)
        }
    }

    func delete(_ measurement: BodyMeasurement) async throws {
        if let errorToThrow { throw errorToThrow }
        measurements.removeAll { $0.id == measurement.id }
    }
}
