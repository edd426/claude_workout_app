import Testing
import SwiftUI
import UIKit
@testable import ClaudeLifter

@Suite("BrandTheme Tests")
struct BrandThemeTests {

    @Test("BrandTheme has all required Anthropic palette properties")
    func brandThemeHasAllColorProperties() {
        _ = BrandTheme.dark
        _ = BrandTheme.light
        _ = BrandTheme.midGray
        _ = BrandTheme.lightGray
        _ = BrandTheme.terracotta
        _ = BrandTheme.blue
        _ = BrandTheme.green
    }

    @Test("BrandTheme has semantic alias properties")
    func brandThemeHasSemanticAliases() {
        _ = BrandTheme.accent
        _ = BrandTheme.cardBackground
        _ = BrandTheme.primaryText
        _ = BrandTheme.secondaryText
        _ = BrandTheme.background
        _ = BrandTheme.success
        _ = BrandTheme.info
    }

    @Test("Terracotta color components are approximately correct")
    func terracottaColorComponentsAreCorrect() throws {
        let color = BrandTheme.terracotta
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(abs(red - 0.851) < 0.01, "Red component should be ~0.851")
        #expect(abs(green - 0.467) < 0.01, "Green component should be ~0.467")
        #expect(abs(blue - 0.341) < 0.01, "Blue component should be ~0.341")
    }

    @Test("Dark color components are approximately correct")
    func darkColorComponentsAreCorrect() throws {
        let uiColor = UIColor(BrandTheme.dark)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(abs(red - 0.078) < 0.01)
        #expect(abs(green - 0.078) < 0.01)
        #expect(abs(blue - 0.075) < 0.01)
    }

    @Test("Light color components are approximately correct")
    func lightColorComponentsAreCorrect() throws {
        let uiColor = UIColor(BrandTheme.light)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(abs(red - 0.980) < 0.01)
        #expect(abs(green - 0.976) < 0.01)
        #expect(abs(blue - 0.961) < 0.01)
    }

    @Test("accent aliases terracotta")
    func accentAliasesTerracotta() {
        #expect(BrandTheme.accent == BrandTheme.terracotta)
    }

    // MARK: Per-appearance tokens (UI-C1–C3), hex values measured 2026-11-03

    private func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> String {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    @Test("Accent text is darker in light mode and brand terracotta in dark mode", arguments: [
        (UIUserInterfaceStyle.light, "#9A5038"),
        (UIUserInterfaceStyle.dark, "#D97757"),
    ])
    func accentText(style: UIUserInterfaceStyle, expected: String) {
        #expect(hex(BrandTheme.accentText, style) == expected)
    }

    @Test("Card background follows the appearance", arguments: [
        (UIUserInterfaceStyle.light, "#F0EEE6"),
        (UIUserInterfaceStyle.dark, "#1C1C1E"),
    ])
    func cardBackground(style: UIUserInterfaceStyle, expected: String) {
        #expect(hex(BrandTheme.cardBackground, style) == expected)
    }

    @Test("Text-safe semantic colours resolve per appearance", arguments: [
        ("secondaryText", UIUserInterfaceStyle.light, "#6B6A64"),
        ("secondaryText", UIUserInterfaceStyle.dark, "#B0AEA5"),
        ("success", UIUserInterfaceStyle.light, "#4F6B2F"),
        ("success", UIUserInterfaceStyle.dark, "#9CB87A"),
        ("warning", UIUserInterfaceStyle.light, "#9A5B00"),
        ("warning", UIUserInterfaceStyle.dark, "#FFB340"),
        ("info", UIUserInterfaceStyle.light, "#3F6E99"),
        ("info", UIUserInterfaceStyle.dark, "#8AB4DE"),
    ])
    func semanticText(name: String, style: UIUserInterfaceStyle, expected: String) {
        let color: Color = switch name {
        case "secondaryText": BrandTheme.secondaryText
        case "success": BrandTheme.success
        case "warning": BrandTheme.warning
        default: BrandTheme.info
        }
        #expect(hex(color, style) == expected)
    }

    @Test("Completed uses the accent everywhere (UI-C5)")
    func completedIsAccent() {
        #expect(hex(BrandTheme.completed, .light) == hex(BrandTheme.accent, .light))
        #expect(hex(BrandTheme.completed, .dark) == hex(BrandTheme.accent, .dark))
    }
}
