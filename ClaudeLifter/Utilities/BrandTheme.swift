import SwiftUI

enum BrandTheme {
    static let terracotta = Color(red: 0.851, green: 0.467, blue: 0.341)  // #D97757
    static let deepNavy = Color(red: 0.102, green: 0.102, blue: 0.180)    // #1A1A2E
    static let midNavy = Color(red: 0.086, green: 0.129, blue: 0.243)     // #16213E
    static let cream = Color(red: 0.961, green: 0.941, blue: 0.922)       // #F5F0EB
    static let creamSubtle = Color(red: 0.831, green: 0.773, blue: 0.725) // #D4C5B9

    // Semantic aliases
    static let accent = terracotta
    static let cardBackground = midNavy
    static let primaryText = cream
    static let secondaryText = creamSubtle
}
