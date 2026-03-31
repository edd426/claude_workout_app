import Testing
import SwiftUI
@testable import ClaudeLifter

@Suite("BrandTheme Tests")
struct BrandThemeTests {

    @Test("BrandTheme has all required color properties")
    func brandThemeHasAllColorProperties() {
        // These property accesses will fail to compile if any are missing
        _ = BrandTheme.terracotta
        _ = BrandTheme.deepNavy
        _ = BrandTheme.midNavy
        _ = BrandTheme.cream
        _ = BrandTheme.creamSubtle
    }

    @Test("BrandTheme has semantic alias properties")
    func brandThemeHasSemanticAliases() {
        _ = BrandTheme.accent
        _ = BrandTheme.cardBackground
        _ = BrandTheme.primaryText
        _ = BrandTheme.secondaryText
    }

    @Test("Terracotta color components are approximately correct")
    func terracottaColorComponentsAreCorrect() throws {
        let color = BrandTheme.terracotta
        // UIColor allows extracting components
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
}
