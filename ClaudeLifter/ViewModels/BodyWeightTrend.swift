import Foundation

/// One body-weight reading, or one aggregated point (a daily mean, a moving
/// average, a downsampled bucket), in canonical kilograms.
struct WeightSample: Equatable, Sendable {
    let date: Date
    let kilograms: Double
}

/// The current rate of change (issue #152): the least-squares slope of daily
/// means over the trailing window, as kilograms and percent of body weight
/// per week.
struct WeightRate: Equatable, Sendable {
    let kilogramsPerWeek: Double
    /// Relative to the mean of the window's daily means.
    let percentPerWeek: Double
    let daysWithData: Int
}

/// How the current rate compares with the goal rate. "Fast" and "slow" are
/// about progress in the goal's direction: losing faster than a negative goal
/// is `.tooFast`, gaining while trying to lose is `.tooSlow`.
enum WeightGoalStatus: Equatable, Sendable {
    case onTrack, tooFast, tooSlow
}

/// The goal editor's way of choosing a signed %/week goal: a direction plus a
/// positive magnitude, so nobody has to type a minus sign.
enum WeightGoalDirection: Equatable, Sendable, CaseIterable {
    case none, lose, maintain, gain

    init(goal: Double?) {
        switch goal {
        case .none: self = .none
        case .some(let value) where value < 0: self = .lose
        case .some(let value) where value > 0: self = .gain
        default: self = .maintain
        }
    }

    /// The signed goal to store; nil means no goal.
    func goal(magnitude: Double) -> Double? {
        switch self {
        case .none: nil
        case .lose: -abs(magnitude)
        case .maintain: 0
        case .gain: abs(magnitude)
        }
    }
}

enum WeightChartRange: String, CaseIterable, Identifiable, Sendable {
    case month = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    /// The earliest date shown, or nil for the whole history.
    func start(endingAt now: Date, calendar: Calendar) -> Date? {
        let months: Int
        switch self {
        case .month: months = 1
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .year: months = 12
        case .all: return nil
        }
        return calendar.date(byAdding: .month, value: -months, to: now)
    }
}

/// Pure body-weight trend math for the weight screen (#152) and the protein
/// target (#111). Everything here is in kilograms; display units are applied
/// by the caller.
enum BodyWeightTrend {
    static let movingAverageDays = 7
    static let rateWindowDays = 28
    /// ±0.1 %/week counts as on track.
    static let goalTolerance = 0.1

    /// One point per calendar day with data, at the start of that day, holding
    /// the mean of that day's readings. Sorted oldest first. Averaging first
    /// keeps a day with three weigh-ins from outweighing a day with one.
    static func dailyMeans(_ samples: [WeightSample], calendar: Calendar) -> [WeightSample] {
        var sums: [Date: (total: Double, count: Int)] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            let current = sums[day] ?? (0, 0)
            sums[day] = (current.total + sample.kilograms, current.count + 1)
        }
        return sums
            .map { WeightSample(date: $0.key, kilograms: $0.value.total / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }

    /// Trailing moving average over `windowDays` calendar days, inclusive of
    /// the day itself, averaged across the days that have data. One output
    /// point per input day. Calendar-windowed rather than count-windowed,
    /// because the history is sparse: seven readings can span a month.
    static func movingAverage(
        _ daily: [WeightSample],
        windowDays: Int = movingAverageDays,
        calendar: Calendar
    ) -> [WeightSample] {
        guard windowDays > 1 else { return daily }
        var result: [WeightSample] = []
        result.reserveCapacity(daily.count)
        var windowStart = 0
        var sum = 0.0
        for (index, day) in daily.enumerated() {
            sum += day.kilograms
            let earliest = calendar.date(
                byAdding: .day, value: -(windowDays - 1), to: day.date
            ) ?? day.date
            while daily[windowStart].date < earliest {
                sum -= daily[windowStart].kilograms
                windowStart += 1
            }
            let count = index - windowStart + 1
            result.append(WeightSample(date: day.date, kilograms: sum / Double(count)))
        }
        return result
    }

    /// Least-squares slope in kilograms per day, with x in whole calendar days
    /// from the first point. Nil for fewer than two points.
    static func slopePerDay(_ daily: [WeightSample], calendar: Calendar) -> Double? {
        guard daily.count >= 2, let first = daily.first else { return nil }
        let xs = daily.map {
            Double(calendar.dateComponents([.day], from: first.date, to: $0.date).day ?? 0)
        }
        let ys = daily.map(\.kilograms)
        let count = Double(daily.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        var covariance = 0.0
        var variance = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - meanX) * (y - meanY)
            variance += (x - meanX) * (x - meanX)
        }
        guard variance > 0 else { return nil }
        return covariance / variance
    }

    /// The rate over the trailing `windowDays` calendar days ending today.
    /// Nil — "not enough data" — when fewer than two days in the window have
    /// a reading, so the caller never shows a NaN.
    static func currentRate(
        _ samples: [WeightSample],
        now: Date,
        windowDays: Int = rateWindowDays,
        calendar: Calendar
    ) -> WeightRate? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(
            byAdding: .day, value: -(windowDays - 1), to: today
        ) else { return nil }
        let daily = dailyMeans(
            samples.filter { $0.date >= windowStart && $0.date <= now },
            calendar: calendar
        )
        guard let slope = slopePerDay(daily, calendar: calendar) else { return nil }
        let meanWeight = daily.map(\.kilograms).reduce(0, +) / Double(daily.count)
        guard meanWeight > 0 else { return nil }
        let perWeek = slope * 7
        return WeightRate(
            kilogramsPerWeek: perWeek,
            percentPerWeek: perWeek / meanWeight * 100,
            daysWithData: daily.count
        )
    }

    /// Compares the actual rate with a signed goal rate, both in %/week.
    /// Within `tolerance` either side is on track. Beyond it, "too fast"
    /// means further along the goal's direction than planned. A maintenance
    /// goal of zero has no direction, so any drift past tolerance is change
    /// happening too fast.
    static func goalStatus(
        actualPercentPerWeek actual: Double,
        goalPercentPerWeek goal: Double,
        tolerance: Double = goalTolerance
    ) -> WeightGoalStatus {
        let deviation = actual - goal
        // The epsilon keeps 0.35 − 0.25 (0.0999…98 or 0.1000…02) on track.
        if abs(deviation) <= tolerance + 1e-9 { return .onTrack }
        if goal > 0 { return deviation > 0 ? .tooFast : .tooSlow }
        if goal < 0 { return deviation < 0 ? .tooFast : .tooSlow }
        return .tooFast
    }

    /// Averages the series into at most `maxPoints` equal-width time buckets,
    /// each placed at the mean date of its points. A series already within
    /// the cap is returned unchanged. This is what keeps a decade of
    /// HealthKit readings fast to draw.
    static func downsample(_ series: [WeightSample], maxPoints: Int) -> [WeightSample] {
        guard maxPoints > 0, series.count > maxPoints,
              let first = series.first, let last = series.last else { return series }
        let span = last.date.timeIntervalSince(first.date)
        guard span > 0 else { return series }
        let bucketWidth = span / Double(maxPoints)
        var buckets = Array(repeating: (time: 0.0, kilograms: 0.0, count: 0), count: maxPoints)
        for point in series {
            let offset = point.date.timeIntervalSince(first.date)
            let index = min(max(Int(offset / bucketWidth), 0), maxPoints - 1)
            buckets[index].time += offset
            buckets[index].kilograms += point.kilograms
            buckets[index].count += 1
        }
        return buckets.compactMap { bucket in
            guard bucket.count > 0 else { return nil }
            let count = Double(bucket.count)
            return WeightSample(
                date: first.date.addingTimeInterval(bucket.time / count),
                kilograms: bucket.kilograms / count
            )
        }
    }
}
