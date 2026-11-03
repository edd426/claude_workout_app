import Foundation

/// Parsing and wording shared by the Body tab's ViewModels (1.9.0). Pure
/// functions: the caller passes `now` and the calendar, so every string is
/// testable.
enum BodyFormat {
    /// Parses a number typed on a decimal pad. Accepts "84.3" and "84,3",
    /// because the pad's separator follows the locale. Nil for empty,
    /// malformed or non-finite input, never zero.
    static func decimal(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else {
            return nil
        }
        return value
    }

    /// How long ago `date` was, by calendar day, in lower case so it reads
    /// inside a sentence: "today", "yesterday", "12 days ago",
    /// "3 months ago", "over a year ago" (ui-standards UI-E4).
    static func age(of date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<60: return "\(days) days ago"
        case 60..<365: return "\(days / 30) months ago"
        default: return "over a year ago"
        }
    }

    /// Whole calendar days between `date` and `now`; 0 for today or later.
    static func daysSince(_ date: Date, now: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return max(days, 0)
    }

    /// A plain number with at most `maxFractionDigits` decimals and no
    /// trailing zeros: 0.25, 2.5, 10.
    static func number(_ value: Double, maxFractionDigits: Int = 2, locale: Locale = .current) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...maxFractionDigits))
                .locale(locale)
        )
    }
}
