import Foundation
@testable import ClaudeLifter

@MainActor
final class MockBodyWeightRepository: BodyWeightRepository {
    var entries: [BodyWeightEntry] = []
    var errorToThrow: Error?
    var fetchAllCallCount = 0

    func fetchAll() async throws -> [BodyWeightEntry] {
        fetchAllCallCount += 1
        if let errorToThrow { throw errorToThrow }
        return entries.sorted { $0.recordedAt > $1.recordedAt }
    }

    func fetchLatest() async throws -> BodyWeightEntry? {
        if let errorToThrow { throw errorToThrow }
        return entries.max { $0.recordedAt < $1.recordedAt }
    }

    func fetchRange(from start: Date, to end: Date) async throws -> [BodyWeightEntry] {
        if let errorToThrow { throw errorToThrow }
        return entries
            .filter { $0.recordedAt >= start && $0.recordedAt <= end }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    func fetchPending() async throws -> [BodyWeightEntry] {
        if let errorToThrow { throw errorToThrow }
        return entries.filter { $0.syncStatus == .pending }
    }

    func exists(healthKitSampleUUID: UUID) async throws -> Bool {
        if let errorToThrow { throw errorToThrow }
        return entries.contains { $0.healthKitSampleUUID == healthKitSampleUUID }
    }

    func save(_ entry: BodyWeightEntry) async throws {
        if let errorToThrow { throw errorToThrow }
        if !entries.contains(where: { $0.id == entry.id }) {
            entries.append(entry)
        }
    }

    func delete(_ entry: BodyWeightEntry) async throws {
        if let errorToThrow { throw errorToThrow }
        entries.removeAll { $0.id == entry.id }
    }
}
