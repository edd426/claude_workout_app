import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("BodyWeightRepository Tests")
@MainActor
struct BodyWeightRepositoryTests {

    private struct Setup {
        let container: ModelContainer
        let repository: SwiftDataBodyWeightRepository
    }

    private func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        return Setup(
            container: container,
            repository: SwiftDataBodyWeightRepository(context: container.mainContext)
        )
    }

    @Test("Saved entries fetch newest-first")
    func fetchAllNewestFirst() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 84.0, recordedAt: Date(timeIntervalSinceNow: -86_400)
        ))
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 84.4, recordedAt: .now
        ))

        let all = try await setup.repository.fetchAll()
        #expect(all.count == 2)
        #expect(all.first?.weightKg == 84.4)
    }

    @Test("fetchLatest returns the most recent entry")
    func fetchLatestReturnsMostRecent() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 83.0, recordedAt: Date(timeIntervalSinceNow: -172_800)
        ))
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 84.2, recordedAt: Date(timeIntervalSinceNow: -3600)
        ))

        let latest = try await setup.repository.fetchLatest()
        #expect(latest?.weightKg == 84.2)
    }

    @Test("fetchRange returns entries inside the window, oldest-first")
    func fetchRangeFiltersAndSorts() async throws {
        let setup = try makeSetup()
        let now = Date()
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 83.0, recordedAt: now.addingTimeInterval(-40 * 86_400)
        ))
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 83.8, recordedAt: now.addingTimeInterval(-10 * 86_400)
        ))
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 84.4, recordedAt: now.addingTimeInterval(-1 * 86_400)
        ))

        let window = try await setup.repository.fetchRange(
            from: now.addingTimeInterval(-30 * 86_400), to: now
        )
        #expect(window.map(\.weightKg) == [83.8, 84.4])
    }

    @Test("exists(healthKitSampleUUID:) dedups imported samples")
    func healthKitUUIDDedup() async throws {
        let setup = try makeSetup()
        let sampleUUID = UUID()
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 84.1, source: "healthkit", healthKitSampleUUID: sampleUUID
        ))

        #expect(try await setup.repository.exists(healthKitSampleUUID: sampleUUID))
        #expect(try await !setup.repository.exists(healthKitSampleUUID: UUID()))
    }

    @Test("New entries are pending so they reach the push cycle")
    func newEntriesArePending() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyWeightEntry(weightKg: 84.0))

        let pending = try await setup.repository.fetchPending()
        #expect(pending.count == 1)

        pending[0].syncStatus = .synced
        let after = try await setup.repository.fetchPending()
        #expect(after.isEmpty)
    }

    @Test("Delete removes the entry")
    func deleteRemovesEntry() async throws {
        let setup = try makeSetup()
        let entry = BodyWeightEntry(weightKg: 84.0)
        try await setup.repository.save(entry)
        try await setup.repository.delete(entry)

        let all = try await setup.repository.fetchAll()
        #expect(all.isEmpty)
    }
}
