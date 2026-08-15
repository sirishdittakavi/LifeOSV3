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

/// The single bold call-to-action treatment — reserved for the one decisive
/// action on a screen (Save, Done, Create). A deep tonal gradient with an
/// inner top highlight reads as premium; a flat saturated fill reads cheap,
/// so this deliberately avoids a single flat accent-color rectangle.
struct LifeOSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .tracking(0.2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
            .padding(.horizontal, LifeOSSpacing.lg)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color.lifeOSAccent.opacity(0.92),
                        Color.lifeOSAccent,
                        Color.lifeOSAccent.blendedTowardBlack(0.22)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.lifeOSAccent.opacity(configuration.isPressed ? 0.12 : 0.28), radius: configuration.isPressed ? 5 : 10, x: 0, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.lifeOSTap, value: configuration.isPressed)
    }
}

/// A quieter alternative to `LifeOSPrimaryButtonStyle` for actions that
/// matter but shouldn't compete with the screen's one true primary action
/// (e.g. a floating quick-add bar) — tinted text on a soft tinted fill
/// instead of a solid saturated block.
struct LifeOSTonalButtonStyle: ButtonStyle {
    var tint: Color = .lifeOSAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
            .padding(.horizontal, LifeOSSpacing.lg)
            .foregroundStyle(tint)
            .background(tint.opacity(configuration.isPressed ? 0.16 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.lifeOSTap, value: configuration.isPressed)
    }
}

private extension Color {
    /// Darkens toward black by `amount` (0–1) for a richer gradient stop.
    func blendedTowardBlack(_ amount: Double) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let t = CGFloat(amount)
        return Color(red: Double(r * (1 - t)), green: Double(g * (1 - t)), blue: Double(b * (1 - t)))
    }
}

struct LifeOSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
            .padding(.horizontal, LifeOSSpacing.lg)
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemBackground).opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.02 : 0.06), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.lifeOSTap, value: configuration.isPressed)
    }
}

struct LifeOSCompactButtonStyle: ButtonStyle {
    var tint: Color = .lifeOSAccent

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

/// Inline row buttons (Start / Finish / Skip). Deliberately graduated
/// rather than a binary tonal-vs-solid-fill choice: a full solid block next
/// to two pastel siblings reads as one button shouting over the others.
/// `.raised` still reads as "the one to reach for" via a deeper tint,
/// bolder border and subtle glow — never a flat saturated rectangle.
struct LifeOSInlineButtonStyle: ButtonStyle {
    enum Emphasis { case quiet, raised }

    var tint: Color = .lifeOSAccent
    var emphasis: Emphasis = .quiet

    private var isRaised: Bool { emphasis == .raised }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .foregroundStyle(tint)
            .background(tint.opacity(configuration.isPressed ? (isRaised ? 0.30 : 0.18) : (isRaised ? 0.20 : 0.10)))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(tint.opacity(isRaised ? 0.45 : 0), lineWidth: 1.25)
            }
            .shadow(color: isRaised ? tint.opacity(configuration.isPressed ? 0.08 : 0.18) : .clear, radius: 5, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.lifeOSTap, value: configuration.isPressed)
    }
}

extension View {
    /// Shared card shell. Elevated (hairline stroke + soft shadow) rather
    /// than a flat fill, matching `LOCard` — the two intentionally share one
    /// visual language even though `.lifeOSCard()` predates the LO* system.
    func lifeOSCard(cornerRadius: CGFloat = 18, tint: Color = .primary) -> some View {
        padding(LifeOSSpacing.lg)
            .lifeOSElevated(cornerRadius: cornerRadius, tint: tint)
    }

    func lifeOSGlassCard(tint: Color = .lifeOSAccent, cornerRadius: CGFloat = 20) -> some View {
        modifier(LifeOSGlassCardModifier(tint: tint, cornerRadius: cornerRadius))
    }
}

private struct LifeOSGlassCardModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(LifeOSSpacing.lg)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.18 : 0.72),
                                tint.opacity(0.14),
                                .white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: tint.opacity(colorScheme == .dark ? 0.08 : 0.06),
                radius: 18, x: 0, y: 9
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.18 : 0.035),
                radius: 8, x: 0, y: 3
            )
    }
}
