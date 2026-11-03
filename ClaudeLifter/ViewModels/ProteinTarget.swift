import Foundation

/// A daily protein floor derived from body weight (issue #111). Display only:
/// there is no intake log yet, so per-day snapshots wait for #110.
struct ProteinTarget: Equatable, Sendable {
    enum Basis: Equatable, Sendable {
        /// Mean of the daily means in the 7 days ending at the latest reading.
        case sevenDayAverage
        /// Only one day had a reading in that window.
        case latestReading
    }

    /// Whole grams per day.
    let grams: Int
    /// g per kg of body weight.
    let multiplier: Double
    let basisKilograms: Double
    let basis: Basis
    /// When the latest reading behind the target was taken.
    let basisDate: Date
    /// No reading for `ProteinTargetCalculator.staleAfterDays`: the target is
    /// the one that was true at the last weigh-in, shown with a flag.
    let isStale: Bool
}

enum ProteinTargetCalculator {
    /// Morton et al.: fat-free-mass gains plateau beyond ~1.6 g/kg/day.
    static let defaultMultiplier = 1.6
    static let staleAfterDays = 30
    static let averageWindowDays = 7

    /// `multiplier` × the 7-day average weight ending at the latest reading,
    /// or × the latest reading when only one day in that window has data.
    ///
    /// Anchoring the window on the latest reading rather than on `now` is what
    /// makes the stale fallback fall out for free: a month without a weigh-in
    /// still yields the target that was computed at the last one, flagged
    /// stale, never nil or zero. Nil only when there has never been a reading.
    static func target(
        samples: [WeightSample],
        multiplier: Double,
        now: Date,
        calendar: Calendar
    ) -> ProteinTarget? {
        guard let latest = samples.max(by: { $0.date < $1.date }) else { return nil }
        let multiplier = multiplier.isFinite && multiplier > 0 ? multiplier : defaultMultiplier
        let latestDay = calendar.startOfDay(for: latest.date)
        let windowStart = calendar.date(
            byAdding: .day, value: -(averageWindowDays - 1), to: latestDay
        ) ?? latestDay
        let daily = BodyWeightTrend.dailyMeans(
            samples.filter { $0.date >= windowStart && $0.date <= latest.date },
            calendar: calendar
        )

        let basis: ProteinTarget.Basis
        let basisKilograms: Double
        if daily.count >= 2 {
            basis = .sevenDayAverage
            basisKilograms = daily.map(\.kilograms).reduce(0, +) / Double(daily.count)
        } else {
            basis = .latestReading
            basisKilograms = latest.kilograms
        }

        let staleAfter = TimeInterval(staleAfterDays) * 86_400
        return ProteinTarget(
            grams: Int((multiplier * basisKilograms).rounded()),
            multiplier: multiplier,
            basisKilograms: basisKilograms,
            basis: basis,
            basisDate: latest.date,
            isStale: now.timeIntervalSince(latest.date) > staleAfter
        )
    }
}

extension ProteinTarget {
    /// "Target 140 g a day (1.6 g/kg × 87.9 kg)" for the Body tab (#111).
    var summaryText: String {
        let multiplierText = multiplier.formatted(.number.precision(.fractionLength(1)))
        let weightText = basisKilograms.formatted(.number.precision(.fractionLength(1)))
        return "Target \(grams) g a day (\(multiplierText) g/kg × \(weightText) kg)"
    }

    /// Why a stale target is still shown, nil when it is current.
    func staleText(now: Date, calendar: Calendar) -> String? {
        guard isStale else { return nil }
        let age = BodyFormat.age(of: basisDate, now: now, calendar: calendar)
        return "From your last weigh-in, \(age). Log one to update it."
    }
}
