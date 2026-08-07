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

// MARK: - Shared controls

struct LifeOSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LifeOSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
            .padding(.horizontal, 14)
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemBackground).opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LifeOSCompactButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(minWidth: 44, minHeight: 44, alignment: .center)
            .padding(.horizontal, 10)
            .foregroundStyle(tint)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LifeOSInlineButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint.opacity(configuration.isPressed ? 0.78 : 1) : tint.opacity(configuration.isPressed ? 0.18 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

extension View {
    func lifeOSCard(cornerRadius: CGFloat = 18) -> some View {
        padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
