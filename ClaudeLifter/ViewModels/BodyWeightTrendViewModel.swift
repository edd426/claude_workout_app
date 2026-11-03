import Foundation
import Observation

/// Drives the body-weight screen (issue #152): the chart, the 28-day rate, the
/// optional goal rate, and the protein target (#111).
///
/// The whole history is read once (about 2,300 entries, mostly HealthKit,
/// back to 2016) and reduced to plain values; the selected range is then cut
/// and downsampled from those, so switching ranges never touches the store.
/// One plotted point, already in the display unit.
struct WeightChartPoint: Equatable, Identifiable, Sendable {
    let id: Int
    let date: Date
    let value: Double
}

/// One day of the goal-pace band, in the display unit.
struct WeightGoalBandPoint: Equatable, Identifiable, Sendable {
    let id: Int
    let date: Date
    let lower: Double
    let upper: Double
}

@Observable
@MainActor
final class BodyWeightTrendViewModel {
    /// Most points either series draws. Short ranges show every raw reading;
    /// longer ones are averaged into time buckets.
    static let maxChartPoints = 120
    static let proteinMultiplierRange: ClosedRange<Double> = 0.8...3.0
    /// Largest goal either way, in %/week.
    static let maxGoalMagnitude = 1.5

    private let repository: any BodyWeightRepository
    private let settings: SettingsManager
    private let calendar: Calendar
    private let now: () -> Date

    /// Raw readings, oldest first, kilograms.
    private var samples: [WeightSample] = []
    private var dailyMeans: [WeightSample] = []
    private var smoothed: [WeightSample] = []
    private var rangePoints: [WeightSample] = []
    private var rangeAverage: [WeightSample] = []

    private(set) var isLoaded = false
    private(set) var errorMessage: String?
    private(set) var rate: WeightRate?

    var selectedRange: WeightChartRange = .threeMonths {
        didSet { rebuildRange() }
    }

    init(
        repository: any BodyWeightRepository,
        settings: SettingsManager,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.repository = repository
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    func load() async {
        do {
            let entries = try await repository.fetchAll()
            samples = entries
                .map { WeightSample(date: $0.recordedAt, kilograms: $0.weightKg) }
                .sorted { $0.date < $1.date }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your weight history."
            samples = []
        }
        dailyMeans = BodyWeightTrend.dailyMeans(samples, calendar: calendar)
        smoothed = BodyWeightTrend.movingAverage(dailyMeans, calendar: calendar)
        rate = BodyWeightTrend.currentRate(samples, now: now(), calendar: calendar)
        rebuildRange()
        isLoaded = true
    }

    // MARK: - Chart

    var displayUnit: WeightUnit { settings.weightUnit }

    /// Readings for the selected range, in the display unit.
    var chartPoints: [WeightChartPoint] { toDisplay(rangePoints) }

    /// The 7-day moving average for the selected range, in the display unit.
    var averageLine: [WeightChartPoint] { toDisplay(rangeAverage) }

    /// Today's 7-day average, in the display unit.
    var currentAverage: Double? {
        smoothed.last.map { WeightUnit.kg.convert($0.kilograms, to: displayUnit) }
    }

    private func rebuildRange() {
        let start = selectedRange.start(endingAt: now(), calendar: calendar) ?? .distantPast
        let end = now()
        let raw = samples.filter { $0.date >= start && $0.date <= end }
        rangePoints = raw.count <= Self.maxChartPoints
            ? raw
            : BodyWeightTrend.downsample(
                dailyMeans.filter { $0.date >= start && $0.date <= end },
                maxPoints: Self.maxChartPoints
            )
        // The average is computed over the whole history first, so the first
        // point in the range still averages the days just before it.
        rangeAverage = BodyWeightTrend.downsample(
            smoothed.filter { $0.date >= start && $0.date <= end },
            maxPoints: Self.maxChartPoints
        )
    }

    private func toDisplay(_ series: [WeightSample]) -> [WeightChartPoint] {
        let unit = displayUnit
        return series.enumerated().map { index, sample in
            WeightChartPoint(
                id: index,
                date: sample.date,
                value: WeightUnit.kg.convert(sample.kilograms, to: unit)
            )
        }
    }

    // MARK: - Rate and goal

    /// The 28-day rate in the display unit per week.
    var displayRatePerWeek: Double? {
        rate.map { WeightUnit.kg.convert($0.kilogramsPerWeek, to: displayUnit) }
    }

    /// Signed %/week; nil means no goal. Stored in Settings, clamped to
    /// ±`maxGoalMagnitude` and rounded to 0.01 so stepper drift
    /// (0.30000000000000004) never reaches the stored value.
    var goalPercentPerWeek: Double? {
        get { settings.weightGoalPercentPerWeek }
        set {
            settings.weightGoalPercentPerWeek = newValue.map {
                let clamped = min(max($0, -Self.maxGoalMagnitude), Self.maxGoalMagnitude)
                return (clamped * 100).rounded() / 100
            }
        }
    }

    /// Nil when there is no goal or not enough data for a rate.
    var goalStatus: WeightGoalStatus? {
        guard let rate, let goal = goalPercentPerWeek else { return nil }
        return BodyWeightTrend.goalStatus(
            actualPercentPerWeek: rate.percentPerWeek, goalPercentPerWeek: goal
        )
    }

    /// Actual minus goal, in %/week: how far off the goal the rate is.
    var goalDeviation: Double? {
        guard let rate, let goal = goalPercentPerWeek else { return nil }
        return rate.percentPerWeek - goal
    }

    /// The goal as a weight per week at today's 7-day average, display unit.
    var displayGoalPerWeek: Double? {
        guard let goal = goalPercentPerWeek, let currentAverage else { return nil }
        return goal * currentAverage / 100
    }

    // MARK: - Body tab card (1.9.0)

    /// When the newest reading was taken.
    var latestReadingDate: Date? { samples.last?.date }

    /// "2 days ago" (UI-E4), nil with no readings.
    var lastWeighInAge: String? {
        latestReadingDate.map { BodyFormat.age(of: $0, now: now(), calendar: calendar) }
    }

    /// A week without a weigh-in: the card flags the age.
    var isWeighInStale: Bool {
        guard let latestReadingDate else { return false }
        return BodyFormat.daysSince(latestReadingDate, now: now(), calendar: calendar)
            >= Self.staleWeighInDays
    }

    static let staleWeighInDays = 7

    /// "+0.18 kg/wk vs goal -0.25", "+0.18 kg/wk · no goal set", or nil when
    /// there is not enough data for a rate.
    var rateSummary: String? {
        guard let perWeek = displayRatePerWeek else { return nil }
        let unit = displayUnit.rawValue
        let rateText = "\(Self.signed(perWeek)) \(unit)/wk"
        guard let goal = displayGoalPerWeek else { return "\(rateText) · no goal set" }
        return "\(rateText) vs goal \(Self.signed(goal))"
    }

    /// Where the weight would be on goal pace, ± the on-track tolerance,
    /// across the rate window: a cone from the 7-day average on the first
    /// day of the window. Empty with no goal, or without enough data for a
    /// rate (a band from a single reading would suggest a trend there isn't).
    var goalBand: [WeightGoalBandPoint] {
        guard let goal = goalPercentPerWeek, rate != nil else { return [] }
        let today = calendar.startOfDay(for: now())
        guard let windowStart = calendar.date(
            byAdding: .day, value: -(BodyWeightTrend.rateWindowDays - 1), to: today
        ), let anchor = smoothed.first(where: { $0.date >= windowStart }) else { return [] }
        let days = calendar.dateComponents([.day], from: anchor.date, to: today).day ?? 0
        guard days > 0 else { return [] }
        let tolerance = BodyWeightTrend.goalTolerance
        let unit = displayUnit
        return (0...days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: anchor.date) else {
                return nil
            }
            let weeks = Double(offset) / 7
            let low = anchor.kilograms * (1 + (goal - tolerance) * weeks / 100)
            let high = anchor.kilograms * (1 + (goal + tolerance) * weeks / 100)
            return WeightGoalBandPoint(
                id: offset,
                date: date,
                lower: WeightUnit.kg.convert(min(low, high), to: unit),
                upper: WeightUnit.kg.convert(max(low, high), to: unit)
            )
        }
    }

    /// VoiceOver summary of the chart (UI-A4).
    var chartAccessibilitySummary: String {
        let unit = displayUnit.rawValue
        guard let average = currentAverage else { return "No weigh-ins yet" }
        var parts = ["7-day average \(Self.plain(average)) \(unit)"]
        if let perWeek = displayRatePerWeek {
            parts.append("trend \(Self.signed(perWeek)) \(unit) a week")
        }
        if let goal = displayGoalPerWeek {
            parts.append("goal \(Self.signed(goal)) \(unit) a week")
        }
        return parts.joined(separator: ", ")
    }

    private static func signed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
    }

    private static func plain(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    // MARK: - Protein (#111)

    var proteinMultiplier: Double {
        get { settings.proteinMultiplier }
        set {
            let range = Self.proteinMultiplierRange
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            settings.proteinMultiplier = (clamped * 10).rounded() / 10
        }
    }

    var proteinTarget: ProteinTarget? {
        ProteinTargetCalculator.target(
            samples: samples,
            multiplier: settings.proteinMultiplier,
            now: now(),
            calendar: calendar
        )
    }
}
