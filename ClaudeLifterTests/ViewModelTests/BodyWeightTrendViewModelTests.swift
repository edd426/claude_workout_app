import Foundation
import Testing
@testable import ClaudeLifter

@Suite("BodyWeightTrendViewModel")
@MainActor
struct BodyWeightTrendViewModelTests {
    private struct Setup {
        let vm: BodyWeightTrendViewModel
        let settings: SettingsManager
        let repository: MockBodyWeightRepository
    }

    private func makeSetup(
        _ samples: [WeightSample],
        unit: WeightUnit = .kg
    ) -> Setup {
        let repository = MockBodyWeightRepository()
        repository.entries = samples.map {
            BodyWeightEntry(weightKg: $0.kilograms, recordedAt: $0.date, source: "healthkit")
        }
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "bw-trend-\(UUID())")!)
        settings.weightUnit = unit
        let vm = BodyWeightTrendViewModel(
            repository: repository,
            settings: settings,
            calendar: TrendTestClock.calendar,
            now: { TrendTestClock.now }
        )
        return Setup(vm: vm, settings: settings, repository: repository)
    }

    /// Losing 0.5 kg a week from 80 kg, one reading a day for four weeks.
    private var losingHalfAKiloAWeek: [WeightSample] {
        (0..<28).map { TrendTestClock.sample(-27 + $0, 80 - 0.5 / 7 * Double($0)) }
    }

    @Test("Loads the history and reports the 28-day rate")
    func loadsRate() async throws {
        let setup = makeSetup(losingHalfAKiloAWeek)

        await setup.vm.load()

        let rate = try #require(setup.vm.rate)
        #expect(abs(rate.kilogramsPerWeek - (-0.5)) < 1e-9)
        #expect(abs((setup.vm.displayRatePerWeek ?? 0) - (-0.5)) < 1e-9)
        #expect(setup.vm.isLoaded)
    }

    @Test("A decade of readings is downsampled for the long ranges")
    func longRangesAreDownsampled() async {
        let decade = (0..<2_330).map { TrendTestClock.sample(-$0 * 2, 80 + Double($0 % 5) * 0.2) }
        let setup = makeSetup(decade)
        await setup.vm.load()

        setup.vm.selectedRange = .all
        #expect(setup.vm.chartPoints.count <= BodyWeightTrendViewModel.maxChartPoints)
        #expect(setup.vm.averageLine.count <= BodyWeightTrendViewModel.maxChartPoints)
        #expect(setup.vm.chartPoints.count > 60)

        setup.vm.selectedRange = .month
        // Every second day over the last month: raw, not bucketed.
        let monthStart = TrendTestClock.calendar.date(byAdding: .month, value: -1, to: TrendTestClock.now)!
        let expected = decade.filter { $0.date >= monthStart && $0.date <= TrendTestClock.now }.count
        #expect(setup.vm.chartPoints.count == expected)
    }

    @Test("Short ranges plot every raw reading, the average one point per day")
    func shortRangesPlotRawReadings() async {
        let setup = makeSetup([
            TrendTestClock.sample(-1, 80),
            TrendTestClock.sample(0, 81, hour: 6),
            TrendTestClock.sample(0, 82, hour: 12),
        ])
        await setup.vm.load()

        setup.vm.selectedRange = .month

        #expect(setup.vm.chartPoints.map(\.value) == [80, 81, 82])
        #expect(setup.vm.averageLine.map(\.value) == [80, 80.75])
    }

    @Test("Chart and rate follow the display unit")
    func displayUnitConversion() async throws {
        let setup = makeSetup(losingHalfAKiloAWeek, unit: .lbs)
        await setup.vm.load()

        let first = try #require(setup.vm.chartPoints.first)
        #expect(abs(first.value - 80 * 2.20462) < 1e-6)
        #expect(abs((setup.vm.displayRatePerWeek ?? 0) - (-0.5 * 2.20462)) < 1e-6)
    }

    @Test("A goal set on the weight screen is saved to Settings and drives the status")
    func goalPersistsAndDrivesStatus() async {
        let setup = makeSetup(losingHalfAKiloAWeek)
        await setup.vm.load()

        setup.vm.goalPercentPerWeek = -0.5

        #expect(setup.settings.weightGoalPercentPerWeek == -0.5)
        // −0.5 kg/wk at a ~79 kg mean is about −0.63 %/wk: losing faster than planned.
        #expect(setup.vm.goalStatus == .tooFast)
        #expect(setup.vm.goalDeviation.map { $0 < -0.1 } == true)
    }

    @Test("A goal beyond ±1.5 %/week is clamped")
    func goalIsClamped() async {
        let setup = makeSetup(losingHalfAKiloAWeek)

        setup.vm.goalPercentPerWeek = -5

        #expect(setup.settings.weightGoalPercentPerWeek == -1.5)
    }

    @Test("The goal's kg/week equivalent uses the current 7-day average")
    func goalInKilogramsPerWeek() async throws {
        let setup = makeSetup([TrendTestClock.sample(-1, 80), TrendTestClock.sample(0, 80)])
        await setup.vm.load()

        setup.vm.goalPercentPerWeek = 0.25

        #expect(abs(try #require(setup.vm.displayGoalPerWeek) - 0.2) < 1e-9)
    }

    @Test("No goal means no status")
    func noGoalNoStatus() async {
        let setup = makeSetup(losingHalfAKiloAWeek)
        await setup.vm.load()

        #expect(setup.vm.goalPercentPerWeek == nil)
        #expect(setup.vm.goalStatus == nil)
    }

    @Test("A single reading is not enough data, and nothing is NaN")
    func singleReadingIsNotEnoughData() async {
        let setup = makeSetup([TrendTestClock.sample(-2, 80)])
        setup.settings.weightGoalPercentPerWeek = 0.25
        await setup.vm.load()

        #expect(setup.vm.rate == nil)
        #expect(setup.vm.goalStatus == nil)
        #expect(setup.vm.chartPoints.count == 1)
        #expect(setup.vm.chartPoints.allSatisfy { $0.value.isFinite })
        #expect(setup.vm.proteinTarget?.grams == 128)
    }

    @Test("No readings at all is an empty state, not an error")
    func noReadings() async {
        let setup = makeSetup([])
        await setup.vm.load()

        #expect(setup.vm.isLoaded)
        #expect(setup.vm.chartPoints.isEmpty)
        #expect(setup.vm.rate == nil)
        #expect(setup.vm.proteinTarget == nil)
        #expect(setup.vm.errorMessage == nil)
    }

    @Test("Changing the protein multiplier updates the target and the setting")
    func multiplierChange() async {
        let setup = makeSetup([TrendTestClock.sample(-1, 80), TrendTestClock.sample(0, 80)])
        await setup.vm.load()
        #expect(setup.vm.proteinTarget?.grams == 128)

        setup.vm.proteinMultiplier = 2.0

        #expect(setup.settings.proteinMultiplier == 2.0)
        #expect(setup.vm.proteinTarget?.grams == 160)
    }

    @Test("The protein multiplier stays within 0.8–3.0 g/kg")
    func multiplierIsClamped() {
        let setup = makeSetup([])

        setup.vm.proteinMultiplier = 10
        #expect(setup.settings.proteinMultiplier == 3.0)

        setup.vm.proteinMultiplier = 0.1
        #expect(setup.settings.proteinMultiplier == 0.8)
    }

    @Test("A failed read reports an error instead of an empty chart")
    func failedReadReportsError() async {
        let setup = makeSetup([])
        setup.repository.errorToThrow = NSError(domain: "test", code: 1)

        await setup.vm.load()

        #expect(setup.vm.errorMessage != nil)
    }
}

@Suite("BodyWeightViewModel protein target")
@MainActor
struct BodyWeightCardProteinTests {
    private func makeVM(
        _ entries: [(daysAgo: Double, kilograms: Double)]
    ) -> (BodyWeightViewModel, SettingsManager) {
        let repository = MockBodyWeightRepository()
        repository.entries = entries.map {
            BodyWeightEntry(
                weightKg: $0.kilograms,
                recordedAt: Date(timeIntervalSinceNow: -$0.daysAgo * 86_400)
            )
        }
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "bw-protein-\(UUID())")!)
        let vm = BodyWeightViewModel(
            repository: repository, healthKit: MockHealthKitService(), settings: settings
        )
        return (vm, settings)
    }

    @Test("The Home card shows the target from recent weigh-ins")
    func cardShowsTarget() async {
        let (vm, _) = makeVM([(1, 80), (0, 82)])

        await vm.load()

        // 1.6 × mean(80, 82) = 129.6
        #expect(vm.proteinTarget?.grams == 130)
        #expect(vm.proteinTarget?.isStale == false)
    }

    @Test("The Home card keeps the last target, flagged stale, after 30 days without a weigh-in")
    func cardKeepsStaleTarget() async {
        let (vm, _) = makeVM([(41, 82), (40, 80)])

        await vm.load()

        #expect(vm.proteinTarget?.grams == 130)
        #expect(vm.proteinTarget?.isStale == true)
    }

    @Test("The Home card follows a multiplier change without reloading")
    func cardFollowsMultiplier() async {
        let (vm, settings) = makeVM([(0, 80)])
        await vm.load()

        settings.proteinMultiplier = 2.0

        #expect(vm.proteinTarget?.grams == 160)
    }
}
