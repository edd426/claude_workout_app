import Foundation

/// Pure unit conversions for the medication log (#164). No state, no I/O.
///
/// Everything converts toward mg, the one unit the history chart plots:
/// - mass: mg ↔ mcg ↔ g
/// - tablets: count × strength per tablet
/// - liquid: mL × concentration (mg/mL)
/// - vial mix: concentration = vial mg ÷ diluent mL
/// - U-100 syringe units: units ÷ 100 = mL, then through the concentration
///
/// `computedMg` is nil, never a guess, when there is nothing honest to
/// compute: IU (no conversion exists), mL or syringe units with no known
/// concentration, tablets with no strength, or an amount that is negative or
/// not a finite number.
struct DoseCalculator {
    /// U-100 syringes: 100 units = 1 mL.
    static let syringeUnitsPerMl = 100.0

    static func convert(_ value: Double, from: MassUnit, to: MassUnit) -> Double {
        value * micrograms(per: from) / micrograms(per: to)
    }

    /// Concentration of a vial the user mixed. Nil unless both values are
    /// positive and finite — a vial with no diluent has no concentration.
    static func concentration(vialAmountMg: Double, diluentMl: Double) -> Double? {
        guard vialAmountMg.isFinite, diluentMl.isFinite,
              vialAmountMg > 0, diluentMl > 0 else { return nil }
        return vialAmountMg / diluentMl
    }

    static func mg(tablets: Double, strengthMg: Double) -> Double {
        tablets * strengthMg
    }

    static func mg(milliliters: Double, concentrationMgPerMl: Double) -> Double {
        milliliters * concentrationMgPerMl
    }

    static func milliliters(syringeUnits: Double) -> Double {
        syringeUnits / syringeUnitsPerMl
    }

    /// The mg a dose represents, or nil when it cannot be computed honestly.
    static func computedMg(
        amount: Double,
        unit: DoseUnit,
        tabletStrengthMg: Double?,
        concentrationMgPerMl: Double?
    ) -> Double? {
        guard amount.isFinite, amount >= 0 else { return nil }
        switch unit {
        case .mg:
            return amount
        case .mcg:
            return convert(amount, from: .mcg, to: .mg)
        case .g:
            return convert(amount, from: .g, to: .mg)
        case .tablet:
            guard let strength = usable(tabletStrengthMg) else { return nil }
            return mg(tablets: amount, strengthMg: strength)
        case .mL:
            guard let concentration = usable(concentrationMgPerMl) else { return nil }
            return mg(milliliters: amount, concentrationMgPerMl: concentration)
        case .syringeUnits:
            guard let concentration = usable(concentrationMgPerMl) else { return nil }
            return mg(milliliters: milliliters(syringeUnits: amount), concentrationMgPerMl: concentration)
        case .IU:
            return nil
        }
    }

    /// Integer factors, so mcg ↔ mg ↔ g stays exact in floating point
    /// (0.001 is not representable; 1000 is).
    private static func micrograms(per unit: MassUnit) -> Double {
        switch unit {
        case .mcg: return 1
        case .mg: return 1_000
        case .g: return 1_000_000
        }
    }

    /// A strength or concentration is only usable if positive and finite.
    private static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
