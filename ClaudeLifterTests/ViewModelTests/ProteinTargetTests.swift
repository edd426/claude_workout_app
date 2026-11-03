import Foundation
import Testing
@testable import ClaudeLifter

@Suite("ProteinTargetCalculator")
struct ProteinTargetTests {
    private let calendar = TrendTestClock.calendar
    private let now = TrendTestClock.now

    private func target(
        _ samples: [WeightSample],
        multiplier: Double = 1.6
    ) -> ProteinTarget? {
        ProteinTargetCalculator.target(
            samples: samples, multiplier: multiplier, now: now, calendar: calendar
        )
    }

    @Test("Target is the multiplier times the 7-day average weight")
    func targetUsesSevenDayAverage() throws {
        let result = try #require(target([
            TrendTestClock.sample(-4, 80),
            TrendTestClock.sample(-2, 81),
            TrendTestClock.sample(0, 82),
        ]))

        // 1.6 × 81.0 = 129.6
        #expect(result.grams == 130)
        #expect(result.basisKilograms == 81)
        #expect(result.basis == .sevenDayAverage)
        #expect(result.isStale == false)
    }

    @Test("One reading in the window uses the latest weight")
    func targetFallsBackToLatestWeight() throws {
        let result = try #require(target([
            TrendTestClock.sample(-10, 70),
            TrendTestClock.sample(0, 80.4),
        ]))

        // The day -10 reading is outside the 7 days ending today.
        // 1.6 × 80.4 = 128.64
        #expect(result.grams == 129)
        #expect(result.basisKilograms == 80.4)
        #expect(result.basis == .latestReading)
    }

    @Test("Several readings on one day count as one day")
    func sameDayReadingsAreOneDay() throws {
        let result = try #require(target([
            TrendTestClock.sample(0, 80, hour: 7),
            TrendTestClock.sample(0, 81, hour: 20),
        ]))

        #expect(result.basis == .latestReading)
        #expect(result.basisKilograms == 81)
    }

    @Test("Changing the multiplier recomputes the target")
    func multiplierChangeRecomputes() throws {
        let samples = [TrendTestClock.sample(-1, 80), TrendTestClock.sample(0, 80)]

        let standard = try #require(target(samples, multiplier: 1.6))
        let raised = try #require(target(samples, multiplier: 2.0))

        #expect(standard.grams == 128)
        #expect(raised.grams == 160)
        #expect(raised.multiplier == 2.0)
    }

    @Test("No weigh-in for 30 days keeps the last target, flagged stale")
    func staleWeightKeepsLastTarget() throws {
        let result = try #require(target([
            TrendTestClock.sample(-44, 82),
            TrendTestClock.sample(-42, 80),
        ]))

        // The target that was true at the last weigh-in: 1.6 × 81.
        #expect(result.grams == 130)
        #expect(result.grams > 0)
        #expect(result.isStale)
        #expect(result.basisDate == TrendTestClock.day(-42))
    }

    @Test("A weigh-in 29 days ago is not stale")
    func recentWeighInIsFresh() throws {
        let result = try #require(target([TrendTestClock.sample(-29, 80)]))

        #expect(result.isStale == false)
    }

    @Test("No readings at all gives no target rather than zero")
    func noReadingsNoTarget() {
        #expect(target([]) == nil)
    }

    @Test("A non-positive multiplier falls back to the 1.6 g/kg default")
    func invalidMultiplierUsesDefault() throws {
        let result = try #require(target([TrendTestClock.sample(0, 80)], multiplier: 0))

        #expect(result.multiplier == ProteinTargetCalculator.defaultMultiplier)
        #expect(result.grams == 128)
    }
}
