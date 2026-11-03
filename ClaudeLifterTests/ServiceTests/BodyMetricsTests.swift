import Foundation
import Testing
@testable import ClaudeLifter

/// Computed body metrics for #165: waist-to-height ratio (NICE NG246 bands),
/// BMI, and the cm / in / ft-in conversions behind height and waist entry.
@Suite("BodyMetrics Tests")
struct BodyMetricsTests {

    private func isClose(_ a: Double?, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tolerance
    }

    // MARK: - Waist-to-height ratio

    @Test("Waist-to-height ratio is waist ÷ height")
    func ratioIsWaistOverHeight() {
        #expect(isClose(BodyMetrics.waistToHeightRatio(waistCm: 90, heightCm: 180), 0.5))
        #expect(isClose(BodyMetrics.waistToHeightRatio(waistCm: 86.5, heightCm: 182.88), 86.5 / 182.88))
    }

    @Test("No ratio without a usable waist or height", arguments: [
        (Double?.none, Double?.some(180)),
        (Double?.some(90), Double?.none),
        (Double?.some(90), Double?.some(0)),
        (Double?.some(90), Double?.some(-170)),
        (Double?.some(0), Double?.some(180)),
        (Double?.some(.nan), Double?.some(180)),
    ])
    func ratioNeedsBothValues(waist: Double?, height: Double?) {
        #expect(BodyMetrics.waistToHeightRatio(waistCm: waist, heightCm: height) == nil)
    }

    @Test("NICE NG246 band boundaries", arguments: [
        (0.4999, WaistToHeightBand.healthy),
        (0.5, WaistToHeightBand.increased),
        (0.5999, WaistToHeightBand.increased),
        (0.6, WaistToHeightBand.high),
        (0.3, WaistToHeightBand.healthy),
        (0.75, WaistToHeightBand.high),
    ])
    func bandBoundaries(ratio: Double, expected: WaistToHeightBand) {
        #expect(BodyMetrics.band(forWaistToHeightRatio: ratio) == expected)
    }

    /// 39.3 in ÷ 65.5 in is exactly 0.6, but converted through centimetres it
    /// computes as 0.5999999999999999. Floating-point noise must not move
    /// someone down a band.
    @Test("A ratio that is 0.6 up to floating-point noise is still high")
    func bandAbsorbsFloatingPointNoise() throws {
        let waist = LengthConversion.cm(fromInches: 39.3)
        let height = LengthConversion.cm(fromInches: 65.5)
        let ratio = try #require(BodyMetrics.waistToHeightRatio(waistCm: waist, heightCm: height))
        #expect(BodyMetrics.band(forWaistToHeightRatio: ratio) == .high)
    }

    // MARK: - BMI

    @Test("BMI is weight ÷ height² in metres")
    func bmiFormula() {
        #expect(isClose(BodyMetrics.bmi(weightKg: 84, heightCm: 182.88), 84 / (1.8288 * 1.8288)))
        #expect(isClose(BodyMetrics.bmi(weightKg: 72, heightCm: 180), 72 / 3.24))
    }

    @Test("BMI is nil, never zero or a crash, without a usable weight or height", arguments: [
        (Double?.none, Double?.some(180)),
        (Double?.some(84), Double?.none),
        (Double?.none, Double?.none),
        (Double?.some(84), Double?.some(0)),
        (Double?.some(0), Double?.some(180)),
        (Double?.some(-84), Double?.some(180)),
        (Double?.some(84), Double?.some(.infinity)),
    ])
    func bmiNeedsBothValues(weight: Double?, height: Double?) {
        #expect(BodyMetrics.bmi(weightKg: weight, heightCm: height) == nil)
    }

    @Test("BMI uses the latest body-weight entry, and is nil when there is none")
    func bmiFromLatestEntry() {
        let entry = BodyWeightEntry(weightKg: 84, recordedAt: .now)
        #expect(isClose(BodyMetrics.bmi(latest: entry, heightCm: 182.88), 84 / (1.8288 * 1.8288)))
        #expect(BodyMetrics.bmi(latest: nil, heightCm: 182.88) == nil)
        #expect(BodyMetrics.bmi(latest: entry, heightCm: nil) == nil)
    }

    // MARK: - Length conversions

    @Test("One inch is 2.54 cm")
    func inchIs254() {
        #expect(isClose(LengthConversion.cm(fromInches: 1), 2.54))
        #expect(isClose(LengthConversion.inches(fromCm: 2.54), 1))
    }

    @Test("cm → in → cm round-trips", arguments: [60.0, 86.5, 91.44, 150, 175.3, 182.88, 201.7])
    func cmInchRoundTrip(cm: Double) {
        let inches = LengthConversion.inches(fromCm: cm)
        #expect(isClose(LengthConversion.cm(fromInches: inches), cm))
    }

    @Test("6 ft 0 in is 182.88 cm")
    func sixFootIs18288() {
        #expect(isClose(LengthConversion.cm(feet: 6, inches: 0), 182.88))
        #expect(isClose(LengthConversion.cm(feet: 5, inches: 11), 180.34))
    }

    @Test("182.88 cm reads back as 6 ft 0 in")
    func cmToFeetAndInches() {
        let parts = LengthConversion.feetAndInches(fromCm: 182.88)
        #expect(parts.feet == 6)
        #expect(isClose(parts.inches, 0, tolerance: 1e-6))
    }

    @Test("ft/in → cm → ft/in round-trips for every whole-inch height from 4 ft to 7 ft 11 in")
    func feetInchesRoundTrip() {
        for feet in 4...7 {
            for inches in 0...11 {
                let cm = LengthConversion.cm(feet: feet, inches: Double(inches))
                let back = LengthConversion.feetAndWholeInches(fromCm: cm)
                #expect(back.feet == feet && back.inches == inches, "\(feet) ft \(inches) in → \(cm) cm → \(back)")
            }
        }
    }

    @Test("Rounding to whole inches carries into the next foot instead of showing 12 in")
    func wholeInchesCarry() {
        // 182.5 cm = 71.85 in → 72 in → 6 ft 0 in, not 5 ft 12 in.
        let parts = LengthConversion.feetAndWholeInches(fromCm: 182.5)
        #expect(parts.feet == 6)
        #expect(parts.inches == 0)
        // 180 cm = 70.87 in → 71 in → 5 ft 11 in.
        let other = LengthConversion.feetAndWholeInches(fromCm: 180)
        #expect(other.feet == 5)
        #expect(other.inches == 11)
    }
}
