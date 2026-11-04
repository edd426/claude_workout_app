import Foundation

/// Text for the active-workout cards and set rows, kept out of the views so
/// it is testable and so `body` does no formatting work beyond reading a
/// string (ui-standards UI-E5).
enum SetEntryText {
    /// One set's values, for summaries.
    struct Entry: Equatable, Sendable {
        /// Nil means bodyweight.
        let weight: Double?
        let unit: WeightUnit
        let reps: Int?
    }

    /// A weight without trailing zeros or grouping: "80", "22.5", "1250".
    static func number(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(
            .number.locale(locale).grouping(.never).precision(.fractionLength(0...2))
        )
    }

    /// PREVIOUS: "80 × 8", "BW × 12" for bodyweight, "60 × –" with no reps.
    static func previous(_ previous: AutoFillResult, locale: Locale = .current) -> String {
        let weight = previous.weight.map { number($0, locale: locale) } ?? "BW"
        let reps = previous.reps.map(String.init) ?? "–"
        return "\(weight) × \(reps)"
    }

    /// PREVIOUS with last session's drift spelled out (#144): "12 × 12 → 8"
    /// reads "last time 12 reps, the plan is 8", where an unexplained glyph
    /// did not.
    static func previous(
        _ previous: AutoFillResult,
        driftTarget: Int?,
        locale: Locale = .current
    ) -> String {
        let base = Self.previous(previous, locale: locale)
        guard let driftTarget else { return base }
        return "\(base) → \(driftTarget)"
    }

    /// The card header's plan: "3 × 8 · 90 s".
    static func target(_ target: PlannedTarget) -> String {
        let rest = target.restSeconds > 0 ? " · \(target.restSeconds) s" : ""
        return "\(target.sets) × \(target.reps)\(rest)"
    }

    /// "3 × 8 @ 80 kg"; ranges when the sets differ ("3 × 5–8 @ 75–85 kg");
    /// "@ BW" for bodyweight. Nil for no sets.
    static func summary(of entries: [Entry], locale: Locale = .current) -> String? {
        guard !entries.isEmpty else { return nil }
        let reps = range(entries.compactMap(\.reps).map(Double.init), locale: locale) ?? "–"
        let weighted = entries.filter { $0.weight != nil }
        guard let weights = range(weighted.compactMap(\.weight), locale: locale) else {
            return "\(entries.count) × \(reps) @ BW"
        }
        let units = Set(weighted.map(\.unit))
        let unit = units.count == 1 ? units.first?.rawValue ?? "" : ""
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return "\(entries.count) × \(reps) @ \(weights)\(suffix)"
    }

    private static func range(_ values: [Double], locale: Locale) -> String? {
        guard let low = values.min(), let high = values.max() else { return nil }
        if low == high { return number(low, locale: locale) }
        return "\(number(low, locale: locale))–\(number(high, locale: locale))"
    }
}
