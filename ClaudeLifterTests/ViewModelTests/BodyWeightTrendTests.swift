import Foundation
import Testing
@testable import ClaudeLifter

/// Fixed UTC calendar and clock so day boundaries are deterministic.
enum TrendTestClock {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2  // Monday
        return calendar
    }

    /// Wednesday 2026-11-04 18:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_793_815_200)

    /// `offset` whole days from today's date, at `hour` UTC.
    static func day(_ offset: Int, hour: Int = 8) -> Date {
        let today = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return day.addingTimeInterval(Double(hour) * 3_600)
    }

    static func sample(_ offset: Int, _ kilograms: Double, hour: Int = 8) -> WeightSample {
        WeightSample(date: day(offset, hour: hour), kilograms: kilograms)
    }
}

@Suite("BodyWeightTrend")
struct BodyWeightTrendTests {
    private let calendar = TrendTestClock.calendar
    private let now = TrendTestClock.now

    // MARK: - Daily means and moving average

    @Test("Daily means average every reading taken on the same day")
    func dailyMeansAverageSameDay() {
        let samples = [
            TrendTestClock.sample(-1, 81.0),
            TrendTestClock.sample(-2, 80.0, hour: 7),
            TrendTestClock.sample(-2, 82.0, hour: 21),
        ]

        let daily = BodyWeightTrend.dailyMeans(samples, calendar: calendar)

        #expect(daily.map(\.kilograms) == [81.0, 81.0])
        #expect(daily.map(\.date) == [
            calendar.startOfDay(for: TrendTestClock.day(-2)),
            calendar.startOfDay(for: TrendTestClock.day(-1)),
        ])
    }

    @Test("Moving average covers seven calendar days, not seven readings")
    func movingAverageIsCalendarWindowed() {
        let daily = BodyWeightTrend.dailyMeans([
            TrendTestClock.sample(-10, 90),
            TrendTestClock.sample(-6, 80),
            TrendTestClock.sample(-3, 82),
            TrendTestClock.sample(0, 84),
        ], calendar: calendar)

        let average = BodyWeightTrend.movingAverage(daily, calendar: calendar)

        // Day -6's window is days -12...-6: the -10 and -6 readings.
        // Today's window is days -6...0: the -6, -3 and 0 readings.
        #expect(average.map(\.kilograms) == [90, 85, 81, 82])
        #expect(average.map(\.date) == daily.map(\.date))
    }

    // MARK: - Rate

    @Test("Least-squares slope of perfectly linear data is exact")
    func slopeOfLinearData() throws {
        let samples = (0..<28).map { TrendTestClock.sample(-27 + $0, 80 + 0.05 * Double($0)) }

        let rate = try #require(BodyWeightTrend.currentRate(samples, now: now, calendar: calendar))

        #expect(abs(rate.kilogramsPerWeek - 0.35) < 1e-9)
        // Mean of 80.00...81.35 is 80.675.
        #expect(abs(rate.percentPerWeek - 0.35 / 80.675 * 100) < 1e-9)
        #expect(rate.daysWithData == 28)
    }

    @Test("Rate only looks at the last 28 days")
    func rateIgnoresOlderReadings() throws {
        let old = (40..<60).map { TrendTestClock.sample(-$0, 100 - Double($0)) }
        let recent = [TrendTestClock.sample(-14, 80), TrendTestClock.sample(0, 79)]

        let rate = try #require(BodyWeightTrend.currentRate(old + recent, now: now, calendar: calendar))

        #expect(rate.daysWithData == 2)
        #expect(abs(rate.kilogramsPerWeek - (-0.5)) < 1e-9)
    }

    @Test("Sparse readings use the gaps between days, not reading counts")
    func rateHandlesSparseReadings() throws {
        // One or two readings a week, as HealthKit history often is.
        let samples = [
            TrendTestClock.sample(-27, 82.0),
            TrendTestClock.sample(-20, 81.5),
            TrendTestClock.sample(-13, 81.0),
            TrendTestClock.sample(-6, 80.5),
        ]

        let rate = try #require(BodyWeightTrend.currentRate(samples, now: now, calendar: calendar))

        #expect(abs(rate.kilogramsPerWeek - (-0.5)) < 1e-9)
    }

    @Test("Fewer than two days with data is not enough data", arguments: [
        [WeightSample](),
        [TrendTestClock.sample(-3, 80)],
        [TrendTestClock.sample(-3, 80, hour: 7), TrendTestClock.sample(-3, 81, hour: 20)],
        [TrendTestClock.sample(-40, 80), TrendTestClock.sample(-35, 81)],
    ])
    func notEnoughData(samples: [WeightSample]) {
        #expect(BodyWeightTrend.currentRate(samples, now: now, calendar: calendar) == nil)
    }

    @Test("Two days with data is enough for a rate")
    func twoDaysIsEnough() throws {
        let samples = [TrendTestClock.sample(-7, 80), TrendTestClock.sample(0, 80.5)]

        let rate = try #require(BodyWeightTrend.currentRate(samples, now: now, calendar: calendar))

        #expect(rate.daysWithData == 2)
        #expect(abs(rate.kilogramsPerWeek - 0.5) < 1e-9)
        #expect(rate.percentPerWeek.isFinite)
    }

    // MARK: - Goal status

    @Test("Goal status respects the goal's sign", arguments: [
        // Gaining goal
        (0.30, 0.25, WeightGoalStatus.onTrack),
        (0.50, 0.25, WeightGoalStatus.tooFast),
        (0.05, 0.25, WeightGoalStatus.tooSlow),
        (-0.30, 0.25, WeightGoalStatus.tooSlow),
        // Losing goal: losing faster than planned is "too fast"
        (-0.45, -0.50, WeightGoalStatus.onTrack),
        (-0.80, -0.50, WeightGoalStatus.tooFast),
        (-0.20, -0.50, WeightGoalStatus.tooSlow),
        (0.10, -0.50, WeightGoalStatus.tooSlow),
        // Maintenance: any drift beyond tolerance is change happening too fast
        (0.05, 0.0, WeightGoalStatus.onTrack),
        (0.30, 0.0, WeightGoalStatus.tooFast),
        (-0.30, 0.0, WeightGoalStatus.tooFast),
    ])
    func goalStatus(actual: Double, goal: Double, expected: WeightGoalStatus) {
        #expect(BodyWeightTrend.goalStatus(
            actualPercentPerWeek: actual, goalPercentPerWeek: goal
        ) == expected)
    }

    @Test("Exactly 0.1 %/week off still counts as on track", arguments: [
        (0.35, 0.25), (0.15, 0.25), (-0.6, -0.5), (-0.4, -0.5),
    ])
    func toleranceBoundaryIsInclusive(actual: Double, goal: Double) {
        #expect(BodyWeightTrend.goalStatus(
            actualPercentPerWeek: actual, goalPercentPerWeek: goal
        ) == .onTrack)
    }

    @Test("A signed goal reads back as a direction", arguments: [
        (nil as Double?, WeightGoalDirection.none),
        (-0.5, WeightGoalDirection.lose),
        (0.0, WeightGoalDirection.maintain),
        (0.25, WeightGoalDirection.gain),
    ])
    func directionFromGoal(goal: Double?, direction: WeightGoalDirection) {
        #expect(WeightGoalDirection(goal: goal) == direction)
    }

    @Test("A direction and magnitude store as a signed goal", arguments: [
        (WeightGoalDirection.none, nil as Double?),
        (WeightGoalDirection.lose, -0.5),
        (WeightGoalDirection.maintain, 0.0),
        (WeightGoalDirection.gain, 0.5),
    ])
    func goalFromDirection(direction: WeightGoalDirection, expected: Double?) {
        #expect(direction.goal(magnitude: 0.5) == expected)
    }

    // MARK: - Downsampling and ranges

    @Test("Downsampling leaves a short series untouched")
    func downsampleShortSeries() {
        let series = (0..<30).map { TrendTestClock.sample(-$0, 80) }.reversed().map { $0 }

        #expect(BodyWeightTrend.downsample(series, maxPoints: 120) == series)
    }

    @Test("Downsampling caps a decade of readings and keeps their level")
    func downsampleLongSeries() {
        // ~2,330 readings back to 2016, like the real HealthKit history.
        let series = (0..<2_330).map { index in
            TrendTestClock.sample(-index * 2, 80 + Double(index % 7) * 0.1)
        }.sorted { $0.date < $1.date }

        let reduced = BodyWeightTrend.downsample(series, maxPoints: 120)

        #expect(reduced.count <= 120)
        #expect(reduced.count > 100)
        #expect(reduced.map(\.date) == reduced.map(\.date).sorted())
        let inputMean = series.map(\.kilograms).reduce(0, +) / Double(series.count)
        let outputMean = reduced.map(\.kilograms).reduce(0, +) / Double(reduced.count)
        #expect(abs(inputMean - outputMean) < 0.05)
        #expect(reduced.allSatisfy { $0.kilograms >= 80 && $0.kilograms <= 80.6 })
    }

    @Test("Chart ranges reach back the right distance", arguments: [
        (WeightChartRange.month, 1),
        (WeightChartRange.threeMonths, 3),
        (WeightChartRange.sixMonths, 6),
        (WeightChartRange.year, 12),
    ])
    func chartRangeStart(range: WeightChartRange, months: Int) {
        let expected = calendar.date(byAdding: .month, value: -months, to: now)
        #expect(range.start(endingAt: now, calendar: calendar) == expected)
    }

    @Test("The All range has no start")
    func allRangeHasNoStart() {
        #expect(WeightChartRange.all.start(endingAt: now, calendar: calendar) == nil)
    }
}
