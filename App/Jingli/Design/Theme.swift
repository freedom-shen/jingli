import SwiftUI

enum Theme {
    static let background = Color(red: 0.03, green: 0.03, blue: 0.04)
    static let card = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let textPrimary = Color(white: 0.96)
    static let textSecondary = Color(white: 0.56)
    static let accent = Color(red: 0.56, green: 0.66, blue: 0.91)
    static let tomato = Color(red: 0.78, green: 0.36, blue: 0.25)

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
