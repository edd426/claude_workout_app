import SwiftUI

enum BrandTheme {
    // Official Anthropic palette
    static let dark = Color(red: 0.078, green: 0.078, blue: 0.075)       // #141413
    static let light = Color(red: 0.980, green: 0.976, blue: 0.961)      // #faf9f5
    static let midGray = Color(red: 0.690, green: 0.682, blue: 0.647)    // #b0aea5
    static let lightGray = Color(red: 0.910, green: 0.902, blue: 0.863)  // #e8e6dc
    static let terracotta = Color(red: 0.851, green: 0.467, blue: 0.341) // #d97757 (unchanged)
    static let blue = Color(red: 0.416, green: 0.608, blue: 0.800)       // #6a9bcc
    static let green = Color(red: 0.471, green: 0.549, blue: 0.365)      // #788c5d

    // Semantic aliases
    static let accent = terracotta
    static let cardBackground = lightGray
    static let primaryText = dark
    static let secondaryText = midGray
    static let background = light
    static let success = green
    static let info = blue
}
