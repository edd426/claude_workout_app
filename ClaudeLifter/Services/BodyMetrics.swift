import Foundation

/// NICE NG246 waist-to-height bands (#165): < 0.5 healthy, 0.5–0.59 increased
/// health risk, ≥ 0.6 high.
enum WaistToHeightBand: String, Sendable, CaseIterable {
    case healthy
    case increased
    case high

    var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .increased: return "Increased risk"
        case .high: return "High risk"
        }
    }
}

/// Computed — never stored — body metrics (#165). Pure functions; nil means
/// "not enough data", never zero and never a crash.
struct BodyMetrics {
    static let increasedRiskThreshold = 0.5
    static let highRiskThreshold = 0.6

    /// waist ÷ height, or nil unless both are positive finite numbers.
    static func waistToHeightRatio(waistCm: Double?, heightCm: Double?) -> Double? {
        guard let waist = positive(waistCm), let height = positive(heightCm) else { return nil }
        return waist / height
    }

    /// The NG246 band for a ratio.
    ///
    /// The ratio is rounded to 6 decimal places first. Measurements entered in
    /// inches and converted through centimetres pick up floating-point noise
    /// (39.3 in ÷ 65.5 in is exactly 0.6 but computes as 0.5999999999999999),
    /// and that noise must not move someone down a band. Six places is far
    /// finer than any tape measure, and keeps 0.5999 in the band it belongs to.
    static func band(forWaistToHeightRatio ratio: Double) -> WaistToHeightBand {
        let rounded = (ratio * 1_000_000).rounded() / 1_000_000
        if rounded < increasedRiskThreshold { return .healthy }
        if rounded < highRiskThreshold { return .increased }
        return .high
    }

    /// BMI = kg ÷ m². A crude measure for someone who lifts — the UI says so.
    static func bmi(weightKg: Double?, heightCm: Double?) -> Double? {
        guard let weight = positive(weightKg), let height = positive(heightCm) else { return nil }
        let metres = height / 100
        return weight / (metres * metres)
    }

    /// BMI from the latest body-weight entry (`BodyWeightRepository.fetchLatest`).
    static func bmi(latest entry: BodyWeightEntry?, heightCm: Double?) -> Double? {
        bmi(weightKg: entry?.weightKg, heightCm: heightCm)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

/// Length conversions for height and circumference entry. Storage is always
/// centimetres; inches and feet/inches are display and entry only.
struct LengthConversion {
    static let cmPerInch = 2.54
    static let inchesPerFoot = 12

    static func inches(fromCm cm: Double) -> Double {
        cm / cmPerInch
    }

    static func cm(fromInches inches: Double) -> Double {
        inches * cmPerInch
    }

    /// 6 ft 0 in → 182.88 cm.
    static func cm(feet: Int, inches: Double) -> Double {
        cm(fromInches: Double(feet * inchesPerFoot) + inches)
    }

    /// Exact split: whole feet plus the remaining (fractional) inches.
    ///
    /// The total is rounded to 1e-6 in first, so 182.88 cm reads as 6 ft 0 in
    /// rather than 5 ft 11.999999999 in.
    static func feetAndInches(fromCm cm: Double) -> (feet: Int, inches: Double) {
        let total = (inches(fromCm: cm) * 1_000_000).rounded() / 1_000_000
        let feet = Int((total / Double(inchesPerFoot)).rounded(.down))
        return (feet, total - Double(feet * inchesPerFoot))
    }

    /// Display split to the nearest whole inch. Rounds the TOTAL first, so
    /// 71.85 in reads 6 ft 0 in, never 5 ft 12 in.
    static func feetAndWholeInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let total = Int(inches(fromCm: cm).rounded())
        return (total / inchesPerFoot, total % inchesPerFoot)
    }
}
