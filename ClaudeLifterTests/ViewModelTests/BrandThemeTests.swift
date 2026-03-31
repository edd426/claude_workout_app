import Testing
import SwiftUI
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

    @Test("cardBackground aliases lightGray")
    func cardBackgroundAliasesLightGray() {
        #expect(BrandTheme.cardBackground == BrandTheme.lightGray)
    }

    @Test("primaryText aliases dark")
    func primaryTextAliasesDark() {
        #expect(BrandTheme.primaryText == BrandTheme.dark)
    }

    @Test("secondaryText aliases midGray")
    func secondaryTextAliasesMidGray() {
        #expect(BrandTheme.secondaryText == BrandTheme.midGray)
    }

    @Test("accent aliases terracotta")
    func accentAliasesTerracotta() {
        #expect(BrandTheme.accent == BrandTheme.terracotta)
    }
}
