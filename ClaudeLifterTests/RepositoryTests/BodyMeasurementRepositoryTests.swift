import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("BodyMeasurementRepository Tests")
@MainActor
struct BodyMeasurementRepositoryTests {

    /// Holds the container for the whole test: a context that outlives its
    /// container traps message-lessly on iOS 26.5.
    private struct Setup {
        let container: ModelContainer
        let repository: SwiftDataBodyMeasurementRepository
        let deletions: DeletionCounter
    }

    @MainActor
    final class DeletionCounter {
        var count = 0
    }

    private func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        let counter = DeletionCounter()
        return Setup(
            container: container,
            repository: SwiftDataBodyMeasurementRepository(
                context: container.mainContext,
                onDeletion: { counter.count += 1 }
            ),
            deletions: counter
        )
    }

    private let day: TimeInterval = 86_400

    @Test("Saved measurements fetch newest-first")
    func fetchAllNewestFirst() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 88, recordedAt: Date(timeIntervalSinceNow: -day)))
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 87, recordedAt: .now))

        let all = try await setup.repository.fetchAll()
        #expect(all.map(\.valueCm) == [87, 88])
    }

    @Test("Listing by site returns only that site, newest-first")
    func fetchBySite() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 88, recordedAt: Date(timeIntervalSinceNow: -day)))
        try await setup.repository.save(BodyMeasurement(site: .hips, valueCm: 101, recordedAt: .now))
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 87, recordedAt: .now))

        let waist = try await setup.repository.fetch(site: .waist)
        #expect(waist.map(\.valueCm) == [87, 88])
    }

    @Test("Listing by site and date range keeps the window, oldest-first for charts")
    func fetchBySiteAndRange() async throws {
        let setup = try makeSetup()
        let now = Date()
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 90, recordedAt: now.addingTimeInterval(-40 * day)))
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 88, recordedAt: now.addingTimeInterval(-10 * day)))
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 87, recordedAt: now.addingTimeInterval(-2 * day)))
        try await setup.repository.save(BodyMeasurement(site: .hips, valueCm: 101, recordedAt: now.addingTimeInterval(-5 * day)))

        let window = try await setup.repository.fetch(
            site: .waist, from: now.addingTimeInterval(-30 * day), to: now
        )
        #expect(window.map(\.valueCm) == [88, 87])
    }

    @Test("Latest for a site is the most recent one, and nil when there is none")
    func fetchLatestForSite() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 88, recordedAt: Date(timeIntervalSinceNow: -day)))
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 87, recordedAt: .now))

        #expect(try await setup.repository.fetchLatest(site: .waist)?.valueCm == 87)
        #expect(try await setup.repository.fetchLatest(site: .calf) == nil)
    }

    @Test("Latest per site has one entry per measured site")
    func fetchLatestPerSite() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 88, recordedAt: Date(timeIntervalSinceNow: -day)))
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 87, recordedAt: .now))
        try await setup.repository.save(BodyMeasurement(site: .arm, valueCm: 38, recordedAt: Date(timeIntervalSinceNow: -3 * day)))

        let latest = try await setup.repository.fetchLatestPerSite()
        #expect(latest.count == 2)
        #expect(latest[.waist]?.valueCm == 87)
        #expect(latest[.arm]?.valueCm == 38)
        #expect(latest[.hips] == nil)
    }

    @Test("Delete removes the measurement and flags a push")
    func deleteRemoves() async throws {
        let setup = try makeSetup()
        let measurement = BodyMeasurement(site: .waist, valueCm: 88)
        try await setup.repository.save(measurement)

        try await setup.repository.delete(measurement)

        #expect(try await setup.repository.fetchAll().isEmpty)
        #expect(setup.deletions.count == 1)
    }

    @Test("Pending lists only measurements not yet pushed")
    func fetchPending() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 88))
        try await setup.repository.save(BodyMeasurement(site: .waist, valueCm: 87, syncStatus: .synced))

        let pending = try await setup.repository.fetchPending()
        #expect(pending.map(\.valueCm) == [88])
    }
}
