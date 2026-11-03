import Foundation

/// Wording for logged doses (#164): "0.25 mL (2.5 mg) · yesterday 21:10".
/// Calendar and locale are injected so every string is testable.
struct MedicationDoseFormatter: Sendable {
    var calendar: Calendar = .current
    var locale: Locale = .current

    /// "0.25 mL", "1 tablet", "1.5 tablets", "10 units", "1000 IU".
    func amount(_ amount: Double, unit: DoseUnit) -> String {
        let number = BodyFormat.number(amount, maxFractionDigits: 3, locale: locale)
        return "\(number) \(symbol(for: unit, amount: amount))"
    }

    /// The amount, plus the computed mg in brackets when the unit is not
    /// already a mass: "0.25 mL (2.5 mg)", "2 tablets (100 mg)".
    func amount(_ amount: Double, unit: DoseUnit, computedMg: Double?) -> String {
        let base = self.amount(amount, unit: unit)
        guard let computedMg, Self.showsComputedMg(for: unit) else { return base }
        return "\(base) (\(BodyFormat.number(computedMg, maxFractionDigits: 3, locale: locale)) mg)"
    }

    /// The amount of a logged dose, with its computed mg.
    func amount(of dose: MedicationDose) -> String {
        guard let unit = dose.unit else {
            return "\(BodyFormat.number(dose.amount, maxFractionDigits: 3, locale: locale)) \(dose.unitRaw)"
        }
        return amount(dose.amount, unit: unit, computedMg: dose.computedMg)
    }

    /// "today 08:05", "yesterday 21:10", "Mon 21:10", "3 Oct 21:10" this
    /// year, "3 Oct 2025" before it.
    func when(_ date: Date, now: Date) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        let time = date.formatted(timeStyle)
        switch days {
        case 0: return "today \(time)"
        case 1: return "yesterday \(time)"
        case 2...6: return "\(date.formatted(baseStyle.weekday(.abbreviated))) \(time)"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            if sameYear {
                return "\(date.formatted(baseStyle.day().month(.abbreviated))) \(time)"
            }
            return date.formatted(baseStyle.day().month(.abbreviated).year())
        }
    }

    /// "0.25 mL (2.5 mg) · yesterday 21:10".
    func summary(of dose: MedicationDose, now: Date) -> String {
        "\(amount(of: dose)) · \(when(dose.takenAt, now: now))"
    }

    /// Masses are already mg-comparable; tablets and volumes are not.
    static func showsComputedMg(for unit: DoseUnit) -> Bool {
        switch unit {
        case .tablet, .mL, .syringeUnits: return true
        case .mg, .mcg, .g, .IU: return false
        }
    }

    private func symbol(for unit: DoseUnit, amount: Double) -> String {
        switch unit {
        case .tablet: return amount == 1 ? "tablet" : "tablets"
        case .syringeUnits: return amount == 1 ? "unit" : "units"
        default: return unit.symbol
        }
    }

    private var baseStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private var timeStyle: Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted, time: .shortened,
            locale: locale, calendar: calendar, timeZone: calendar.timeZone
        )
    }
}
