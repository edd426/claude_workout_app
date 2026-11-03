import SwiftUI
import UIKit

/// Colour tokens. Use the semantic tokens, never the raw palette, for anything
/// that carries meaning (ui-standards UI-C2). Every semantic token resolves per
/// appearance, so the app works in light and dark mode (UI-C1).
///
/// Contrast (WCAG, measured 2026-11-03), light on #FFFFFF / card #F0EEE6,
/// dark on #000000 / card #1C1C1E:
/// - `accentText`: 5.9 / 5.1 light, 6.7 / 5.5 dark. Use for text below `.title3` bold.
/// - `accent`: 3.1 on white. Fills, icons and bold text ≥ 14 pt only (UI-C3).
///   White bold labels on an `accent` fill are 3.1:1, which passes for large text only.
/// - `secondaryText` 5.4 / 4.7, `success` 6.0 / 5.2, `warning` 5.4 / 4.7,
///   `info` 5.4 / 4.6 in light; all above 6 in dark.
enum BrandTheme {
    // MARK: Raw palette (Anthropic). Not for meaning; prefer the tokens below.
    static let dark = Color(hex: 0x141413)
    static let light = Color(hex: 0xFAF9F5)
    static let midGray = Color(hex: 0xB0AEA5)
    static let lightGray = Color(hex: 0xE8E6DC)
    static let terracotta = Color(hex: 0xD97757)
    static let blue = Color(hex: 0x6A9BCC)
    static let green = Color(hex: 0x788C5D)

    // MARK: Semantic tokens
    /// Brand fill: prominent buttons, icons, progress, the completed check.
    static let accent = terracotta
    /// Accent-coloured text at body and caption sizes.
    static let accentText = Color(light: 0x9A5038, dark: 0xD97757)
    /// A completed set, exercise or day, in every screen (UI-C5).
    static let completed = accent
    static let cardBackground = Color(light: 0xF0EEE6, dark: 0x1C1C1E)
    static let background = Color(light: 0xFAF9F5, dark: 0x000000)
    static let primaryText = Color(light: 0x141413, dark: 0xFAF9F5)
    static let secondaryText = Color(light: 0x6B6A64, dark: 0xB0AEA5)
    static let success = Color(light: 0x4F6B2F, dark: 0x9CB87A)
    static let warning = Color(light: 0x9A5B00, dark: 0xFFB340)
    static let info = Color(light: 0x3F6E99, dark: 0x8AB4DE)
    /// Destructive actions are system red, never the app tint (UI-P6).
    static let destructive = Color(uiColor: .systemRed)
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A colour that resolves per appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
