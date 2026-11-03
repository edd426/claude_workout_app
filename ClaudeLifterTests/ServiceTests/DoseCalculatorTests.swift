import Foundation
import Testing
@testable import ClaudeLifter

/// Unit conversions for the medication log (#164). Every conversion the dose
/// entry can perform is covered here, including the issue's worked example.
@Suite("DoseCalculator Tests")
struct DoseCalculatorTests {

    private func isClose(_ a: Double?, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tolerance
    }

    // MARK: - Mass units

    struct MassCase: Sendable, CustomStringConvertible {
        let value: Double
        let from: MassUnit
        let to: MassUnit
        let expected: Double
        var description: String { "\(value) \(from) → \(expected) \(to)" }
    }

    @Test("Mass converts between mg, mcg and g", arguments: [
        MassCase(value: 1, from: .mg, to: .mcg, expected: 1000),
        MassCase(value: 500, from: .mcg, to: .mg, expected: 0.5),
        MassCase(value: 0.25, from: .g, to: .mg, expected: 250),
        MassCase(value: 250, from: .mg, to: .g, expected: 0.25),
        MassCase(value: 1, from: .g, to: .mcg, expected: 1_000_000),
        MassCase(value: 2_500, from: .mcg, to: .g, expected: 0.0025),
        MassCase(value: 7.5, from: .mg, to: .mg, expected: 7.5),
    ])
    func massConversion(_ c: MassCase) {
        #expect(isClose(DoseCalculator.convert(c.value, from: c.from, to: c.to), c.expected))
    }

    @Test("Mass conversion round-trips mg → mcg → g → mg")
    func massRoundTrip() {
        let mcg = DoseCalculator.convert(12.5, from: .mg, to: .mcg)
        let g = DoseCalculator.convert(mcg, from: .mcg, to: .g)
        #expect(isClose(DoseCalculator.convert(g, from: .g, to: .mg), 12.5))
    }

    @Test("A dose entered in mcg or g is computed in mg")
    func massDoseComputesMg() {
        #expect(isClose(DoseCalculator.computedMg(amount: 500, unit: .mcg, tabletStrengthMg: nil, concentrationMgPerMl: nil), 0.5))
        #expect(isClose(DoseCalculator.computedMg(amount: 1.5, unit: .g, tabletStrengthMg: nil, concentrationMgPerMl: nil), 1500))
        #expect(isClose(DoseCalculator.computedMg(amount: 20, unit: .mg, tabletStrengthMg: nil, concentrationMgPerMl: nil), 20))
    }

    // MARK: - Tablets

    @Test("Tablets multiply count by strength: 1.5 × 50 mg = 75 mg")
    func tabletsTimesStrength() {
        #expect(isClose(DoseCalculator.mg(tablets: 1.5, strengthMg: 50), 75))
        #expect(isClose(DoseCalculator.computedMg(amount: 1.5, unit: .tablet, tabletStrengthMg: 50, concentrationMgPerMl: nil), 75))
    }

    @Test("A tablet dose with no strength on file has no computed mg")
    func tabletsWithoutStrength() {
        #expect(DoseCalculator.computedMg(amount: 2, unit: .tablet, tabletStrengthMg: nil, concentrationMgPerMl: nil) == nil)
    }

    // MARK: - Liquids

    @Test("Vial mix: 10 mg + 2 mL diluent → 5 mg/mL")
    func vialMixConcentration() {
        #expect(isClose(DoseCalculator.concentration(vialAmountMg: 10, diluentMl: 2), 5))
    }

    @Test("A vial with no diluent has no concentration, not a division by zero")
    func vialMixWithoutDiluent() {
        #expect(DoseCalculator.concentration(vialAmountMg: 10, diluentMl: 0) == nil)
        #expect(DoseCalculator.concentration(vialAmountMg: 10, diluentMl: -1) == nil)
        #expect(DoseCalculator.concentration(vialAmountMg: 0, diluentMl: 2) == nil)
    }

    @Test("mL × concentration: 0.5 mL at 5 mg/mL = 2.5 mg")
    func millilitresTimesConcentration() {
        #expect(isClose(DoseCalculator.mg(milliliters: 0.5, concentrationMgPerMl: 5), 2.5))
        #expect(isClose(DoseCalculator.computedMg(amount: 0.5, unit: .mL, tabletStrengthMg: nil, concentrationMgPerMl: 5), 2.5))
    }

    @Test("U-100 syringe units: 50 units → 0.5 mL → 2.5 mg at 5 mg/mL")
    func syringeUnitsThroughConcentration() {
        #expect(isClose(DoseCalculator.milliliters(syringeUnits: 50), 0.5))
        #expect(isClose(DoseCalculator.milliliters(syringeUnits: 100), 1))
        #expect(isClose(DoseCalculator.computedMg(amount: 50, unit: .syringeUnits, tabletStrengthMg: nil, concentrationMgPerMl: 5), 2.5))
    }

    @Test("The issue's worked example end to end: vial → concentration → mL and units → mg")
    func issueWorkedExample() throws {
        let concentration = try #require(DoseCalculator.concentration(vialAmountMg: 10, diluentMl: 2))
        #expect(isClose(DoseCalculator.computedMg(amount: 0.5, unit: .mL, tabletStrengthMg: nil, concentrationMgPerMl: concentration), 2.5))
        #expect(isClose(DoseCalculator.computedMg(amount: 50, unit: .syringeUnits, tabletStrengthMg: nil, concentrationMgPerMl: concentration), 2.5))
    }

    @Test("mL and syringe units with no known concentration have no computed mg")
    func liquidWithoutConcentration() {
        #expect(DoseCalculator.computedMg(amount: 0.5, unit: .mL, tabletStrengthMg: nil, concentrationMgPerMl: nil) == nil)
        #expect(DoseCalculator.computedMg(amount: 50, unit: .syringeUnits, tabletStrengthMg: nil, concentrationMgPerMl: nil) == nil)
    }

    // MARK: - IU and invalid input

    @Test("IU is logged as entered and never converted")
    func internationalUnitsNeverConvert() {
        #expect(DoseCalculator.computedMg(amount: 2000, unit: .IU, tabletStrengthMg: 50, concentrationMgPerMl: 5) == nil)
    }

    @Test("A negative or non-finite amount has no computed mg", arguments: [-1.0, Double.nan, Double.infinity])
    func invalidAmount(amount: Double) {
        #expect(DoseCalculator.computedMg(amount: amount, unit: .mg, tabletStrengthMg: nil, concentrationMgPerMl: nil) == nil)
    }

    @Test("A zero dose computes to zero mg, not nil")
    func zeroDose() {
        #expect(DoseCalculator.computedMg(amount: 0, unit: .mL, tabletStrengthMg: nil, concentrationMgPerMl: 5) == 0)
    }
}
