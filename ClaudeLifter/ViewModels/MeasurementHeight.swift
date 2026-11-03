import Foundation

/// How height is entered and shown (#165). Storage is always centimetres in
/// `SettingsManager.heightCm`; this is only the user's preferred style.
enum HeightStyle: String, CaseIterable, Identifiable, Sendable {
    case feetInches
    case centimetres

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feetInches: return "ft / in"
        case .centimetres: return "cm"
        }
    }

    /// The style to start from before the user has picked one: imperial
    /// weight suggests imperial height.
    static func defaultStyle(for weightUnit: WeightUnit) -> HeightStyle {
        weightUnit == .lbs ? .feetInches : .centimetres
    }
}

/// Parsing and display for the height sheet. Nil means "not a usable
/// height", so Save stays disabled rather than storing nonsense.
enum HeightEntry {
    /// Heights from about 3 ft to 8 ft 2 in, generously.
    static let validRangeCm: ClosedRange<Double> = 90...249

    /// Feet and inches as typed. Empty inches means 0; inches may be
    /// fractional but must be under 12.
    static func cm(feetText: String, inchesText: String) -> Double? {
        guard let feet = BodyFormat.decimal(feetText),
              feet >= 0, feet == feet.rounded(.down) else { return nil }
        let trimmedInches = inchesText.trimmingCharacters(in: .whitespaces)
        let inches: Double
        if trimmedInches.isEmpty {
            inches = 0
        } else {
            guard let parsed = BodyFormat.decimal(trimmedInches),
                  parsed >= 0, parsed < Double(LengthConversion.inchesPerFoot) else { return nil }
            inches = parsed
        }
        let cm = LengthConversion.cm(feet: Int(feet), inches: inches)
        return validRangeCm.contains(cm) ? cm : nil
    }

    static func cm(centimetresText: String) -> Double? {
        guard let cm = BodyFormat.decimal(centimetresText), validRangeCm.contains(cm) else {
            return nil
        }
        return cm
    }

    /// "5 ft 11 in" or "180 cm".
    static func text(cm: Double, style: HeightStyle) -> String {
        switch style {
        case .feetInches:
            let split = LengthConversion.feetAndWholeInches(fromCm: cm)
            return "\(split.feet) ft \(split.inches) in"
        case .centimetres:
            return "\(Int(cm.rounded())) cm"
        }
    }

    /// Text-field values to prefill the sheet with, in the given style.
    static func fields(cm: Double, style: HeightStyle) -> (first: String, second: String) {
        switch style {
        case .feetInches:
            let split = LengthConversion.feetAndWholeInches(fromCm: cm)
            return ("\(split.feet)", "\(split.inches)")
        case .centimetres:
            return ("\(Int(cm.rounded()))", "")
        }
    }
}
