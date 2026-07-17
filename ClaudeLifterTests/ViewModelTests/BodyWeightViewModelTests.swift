import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("BodyWeightViewModel Tests")
@MainActor
struct BodyWeightViewModelTests {

    private struct Setup {
        let container: ModelContainer
        let repository: SwiftDataBodyWeightRepository
        let healthKit: MockHealthKitService
        let settings: SettingsManager
        let vm: BodyWeightViewModel
    }

    private func makeSetup(unit: WeightUnit = .kg) throws -> Setup {
        let container = try makeTestContainer()
        let repository = SwiftDataBodyWeightRepository(context: container.mainContext)
        let healthKit = MockHealthKitService()
        let settings = SettingsManager(
            defaults: UserDefaults(suiteName: "bw-vm-\(UUID())")!
        )
        settings.weightUnit = unit
        return Setup(
            container: container,
            repository: repository,
            healthKit: healthKit,
            settings: settings,
            vm: BodyWeightViewModel(
                repository: repository, healthKit: healthKit, settings: settings
            )
        )
    }

    @Test("Logging in lbs stores canonical kilograms, pending for sync")
    func logWeightConvertsToKilograms() async throws {
        let setup = try makeSetup(unit: .lbs)

        await setup.vm.logWeight(185.0, unit: .lbs)

        let saved = try #require(try await setup.repository.fetchLatest())
        #expect(abs(saved.weightKg - 83.91) < 0.05)
        #expect(saved.source == "manual")
        #expect(saved.syncStatus == .pending)
        // And the display value converts back for the card.
        #expect(abs((setup.vm.latestDisplayWeight ?? 0) - 185.0) < 0.1)
    }

    @Test("Successful HealthKit write back-fills the sample UUID for dedup")
    func logWeightStoresHealthKitUUID() async throws {
        let setup = try makeSetup()
        let expectedUUID = setup.healthKit.writeResultUUID

        await setup.vm.logWeight(84.3, unit: .kg)

        let saved = try #require(try await setup.repository.fetchLatest())
        #expect(saved.healthKitSampleUUID == expectedUUID)
        #expect(setup.healthKit.writeBodyMassCalls.count == 1)
        #expect(setup.healthKit.writeBodyMassCalls.first?.kilograms == 84.3)
    }

    @Test("HealthKit failure never blocks the local entry")
    func logWeightSurvivesHealthKitFailure() async throws {
        let setup = try makeSetup()
        setup.healthKit.writeError = NSError(domain: "hk", code: 1)

        await setup.vm.logWeight(84.0, unit: .kg)

        let saved = try #require(try await setup.repository.fetchLatest())
        #expect(saved.weightKg == 84.0)
        #expect(saved.healthKitSampleUUID == nil)
        #expect(setup.vm.errorMessage == nil)
    }

    @Test("HealthKit import creates entries once — re-import dedups by sample UUID")
    func importDedupsBySampleUUID() async throws {
        let setup = try makeSetup()
        let sampleUUID = UUID()
        setup.healthKit.samplesToReturn = [
            HealthKitBodyMassSample(uuid: sampleUUID, kilograms: 83.5, date: .now)
        ]

        await setup.vm.importFromHealthKit()
        await setup.vm.importFromHealthKit()

        let all = try await setup.repository.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.source == "healthkit")
        #expect(all.first?.healthKitSampleUUID == sampleUUID)
    }

    @Test("Delta over a window compares latest against the window's oldest entry")
    func deltaComputation() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 83.0, recordedAt: Date(timeIntervalSinceNow: -6 * 86_400)
        ))
        try await setup.repository.save(BodyWeightEntry(
            weightKg: 84.2, recordedAt: .now
        ))
        await setup.vm.load()

        let delta = try #require(setup.vm.delta(days: 7))
        #expect(abs(delta - 1.2) < 0.01)
        // Only one entry inside a 1-day window → no delta.
        #expect(setup.vm.delta(days: 1) == nil)
    }

    @Test("Unavailable HealthKit is silently skipped for both write and import")
    func unavailableHealthKitSkipped() async throws {
        let setup = try makeSetup()
        setup.healthKit.isAvailable = false
        setup.healthKit.samplesToReturn = [
            HealthKitBodyMassSample(uuid: UUID(), kilograms: 80, date: .now)
        ]

        await setup.vm.logWeight(84.0, unit: .kg)
        await setup.vm.importFromHealthKit()

        #expect(setup.healthKit.writeBodyMassCalls.isEmpty)
        let all = try await setup.repository.fetchAll()
        #expect(all.count == 1)  // only the manual entry
        #expect(all.first?.healthKitSampleUUID == nil)
    }
}
