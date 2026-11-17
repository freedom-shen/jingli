import SwiftUI

/// 与 macOS 端同一套色板，iOS 上只换布局，不换颜色语义。
enum Tokens {
    static let bg = Color(red: 0.031, green: 0.031, blue: 0.039)      // #08080A
    static let card = Color(red: 0.075, green: 0.075, blue: 0.086)    // #131316
    static let cardAlt = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let line = Color.white.opacity(0.07)

    static let text = Color(white: 0.95)
    static let text2 = Color(white: 0.60)
    static let text3 = Color(white: 0.42)

    static let accent = Color(red: 0.561, green: 0.659, blue: 0.910)  // #8FA8E8
    static let tomato = Color(red: 0.780, green: 0.361, blue: 0.251)  // #C75C40
    static let green = Color(red: 0.361, green: 0.620, blue: 0.459)   // #5C9E75

    static func projectColor(_ name: String) -> Color {
        switch name {
        case "amber": return Color(red: 0.86, green: 0.67, blue: 0.36)
        case "blue": return Color(red: 0.47, green: 0.63, blue: 0.91)
        case "rose": return Color(red: 0.86, green: 0.52, blue: 0.58)
        case "violet": return Color(red: 0.68, green: 0.55, blue: 0.90)
        case "slate": return Color(red: 0.55, green: 0.58, blue: 0.64)
        default: return Color(red: 0.56, green: 0.72, blue: 0.58)
        }
    }
}
