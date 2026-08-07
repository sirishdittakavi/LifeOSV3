//
//  ColorToken.swift
//  LifeOS
//

import SwiftUI

enum ColorToken {
    static func color(for token: String) -> Color {
        switch token {
        case "orange": return .orange
        case "blue": return .blue
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "pink": return .pink
        case "yellow": return .yellow
        case "teal": return .teal
        case "mint": return .mint
        default: return .gray
        }
    }
}

struct CategoryIconOption: Identifiable {
    let name: String
    let symbol: String
    var id: String { symbol }
}

enum CategoryAppearanceOptions {
    static let colors = ["orange", "blue", "purple", "indigo", "red", "green", "teal", "cyan", "pink", "yellow", "mint"]

    static let icons = [
        CategoryIconOption(name: "Target", symbol: "target"),
        CategoryIconOption(name: "Baseball", symbol: "figure.baseball"),
        CategoryIconOption(name: "Running", symbol: "figure.run"),
        CategoryIconOption(name: "Mobility", symbol: "figure.flexibility"),
        CategoryIconOption(name: "Strength", symbol: "dumbbell.fill"),
        CategoryIconOption(name: "Health", symbol: "heart.fill"),
        CategoryIconOption(name: "Nutrition", symbol: "fork.knife"),
        CategoryIconOption(name: "School", symbol: "book.fill"),
        CategoryIconOption(name: "Learning", symbol: "lightbulb.fill"),
        CategoryIconOption(name: "Software", symbol: "chevron.left.forwardslash.chevron.right"),
        CategoryIconOption(name: "Work", symbol: "briefcase.fill"),
        CategoryIconOption(name: "Music", symbol: "music.note"),
        CategoryIconOption(name: "Leisure", symbol: "gamecontroller.fill"),
        CategoryIconOption(name: "Family", symbol: "person.2.fill"),
        CategoryIconOption(name: "Recovery", symbol: "bed.double.fill"),
        CategoryIconOption(name: "Weight", symbol: "scalemass.fill")
    ]
}
