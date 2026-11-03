import Foundation
import Testing
@testable import ClaudeLifter

/// The Body tab's weight and protein cards (1.9.0), built on the #152 and
/// #111 ViewModels.
@Suite("Body tab weight and protein cards")
@MainActor
struct BodyWeightCardSummaryTests {
    private func makeVM(_ samples: [WeightSample], goal: Double? = nil) -> (BodyWeightTrendViewModel, SettingsManager) {
        let repository = MockBodyWeightRepository()
        repository.entries = samples.map {
            BodyWeightEntry(weightKg: $0.kilograms, recordedAt: $0.date, source: "manual")
        }
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "body-card-\(UUID())")!)
        settings.weightGoalPercentPerWeek = goal
        let vm = BodyWeightTrendViewModel(
            repository: repository,
            settings: settings,
            calendar: TrendTestClock.calendar,
            now: { TrendTestClock.now }
        )
        return (vm, settings)
    }

    /// Losing 0.5 kg a week from 80 kg, one reading a day for four weeks,
    /// the last one two days ago.
    private var losing: [WeightSample] {
        (0..<28).map { TrendTestClock.sample(-29 + $0, 80 - 0.5 / 7 * Double($0)) }
    }

    @Test("The rate line compares the trend with the goal, both per week")
    func rateSummaryWithGoal() async throws {
        let (vm, _) = makeVM(losing, goal: -0.5)
        await vm.load()

        let goalPerWeek = try #require(vm.displayGoalPerWeek)
        let goalText = goalPerWeek.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        let summary = try #require(vm.rateSummary)
        #expect(summary.hasPrefix("-0.5"))
        #expect(summary.hasSuffix("kg/wk vs goal \(goalText)"))
    }

    @Test("Without a goal the rate line says so")
    func rateSummaryWithoutGoal() async {
        let (vm, _) = makeVM(losing)
        await vm.load()
        #expect(vm.rateSummary?.hasSuffix("kg/wk · no goal set") == true)
    }

    @Test("One reading is not a rate")
    func rateSummaryNeedsData() async {
        let (vm, _) = makeVM([TrendTestClock.sample(-1, 80)], goal: -0.5)
        await vm.load()
        #expect(vm.rateSummary == nil)
        #expect(vm.goalBand.isEmpty)
    }

    @Test("The staleness label gives the last weigh-in's age")
    func lastWeighInAge() async {
        let (vm, _) = makeVM(losing)
        await vm.load()
        #expect(vm.lastWeighInAge == "2 days ago")
        #expect(!vm.isWeighInStale)

        let (old, _) = makeVM([TrendTestClock.sample(-8, 80)])
        await old.load()
        #expect(old.lastWeighInAge == "8 days ago")
        #expect(old.isWeighInStale)
    }

    @Test("The goal band is a cone from the 28-day window's start at goal pace ± tolerance")
    func goalBand() async throws {
        let (vm, _) = makeVM(losing, goal: -0.5)
        await vm.load()

        let band = vm.goalBand
        let first = try #require(band.first)
        let last = try #require(band.last)
        // The window is the last 28 days: today and the 27 before it.
        #expect(band.count == 28)
        #expect(first.lower == first.upper)
        #expect(last.lower < last.upper)
        // 27 days at -0.5 %/wk ± 0.1 from the anchor.
        let weeks = 27.0 / 7
        #expect(abs(last.upper / first.upper - (1 + (-0.4) * weeks / 100)) < 1e-9)
        #expect(abs(last.lower / first.lower - (1 + (-0.6) * weeks / 100)) < 1e-9)
    }

    @Test("No goal, no band")
    func noGoalNoBand() async {
        let (vm, _) = makeVM(losing)
        await vm.load()
        #expect(vm.goalBand.isEmpty)
    }

    @Test("The chart's spoken summary carries the average, trend and goal")
    func chartSummary() async {
        let (vm, _) = makeVM(losing, goal: -0.5)
        await vm.load()
        let summary = vm.chartAccessibilitySummary
        #expect(summary.hasPrefix("7-day average"))
        #expect(summary.contains("trend -0.50 kg a week"))
        #expect(summary.contains("goal -"))
    }

    @Test("The protein card reads the target and the sum behind it")
    func proteinText() throws {
        let samples = [TrendTestClock.sample(0, 87.5)]
        let target = try #require(ProteinTargetCalculator.target(
            samples: samples, multiplier: 1.6,
            now: TrendTestClock.now, calendar: TrendTestClock.calendar
        ))
        #expect(target.summaryText == "Target 140 g a day (1.6 g/kg × 87.5 kg)")
        #expect(target.staleText(now: TrendTestClock.now, calendar: TrendTestClock.calendar) == nil)
    }

    @Test("A stale protein target says how old its weigh-in is")
    func proteinStale() throws {
        let samples = [TrendTestClock.sample(-34, 80)]
        let target = try #require(ProteinTargetCalculator.target(
            samples: samples, multiplier: 2.0,
            now: TrendTestClock.now, calendar: TrendTestClock.calendar
        ))
        #expect(target.summaryText == "Target 160 g a day (2.0 g/kg × 80.0 kg)")
        #expect(target.staleText(now: TrendTestClock.now, calendar: TrendTestClock.calendar)
            == "From your last weigh-in, 34 days ago. Log one to update it.")
    }

    @Test("The protein card follows a multiplier change")
    func proteinFollowsMultiplier() async {
        let (vm, settings) = makeVM([TrendTestClock.sample(0, 87.5)])
        await vm.load()
        settings.proteinMultiplier = 2.0
        #expect(vm.proteinTarget?.summaryText == "Target 175 g a day (2.0 g/kg × 87.5 kg)")
    }
}
