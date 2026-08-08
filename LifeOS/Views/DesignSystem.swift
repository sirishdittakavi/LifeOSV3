//
//  DesignSystem.swift
//  LifeOS
//
//  Shared layout and motion tokens complement ColorToken, which remains the
//  source of user-selected Plan colours. Pillar gradients are reserved for
//  aggregate and hero views so custom Plan identities are never overwritten.
//

import SwiftUI

enum LifeOSSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum LifeOSRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}

extension Animation {
    static var lifeOSTap: Animation { .spring(response: 0.32, dampingFraction: 0.72) }
    static var lifeOSReveal: Animation { .spring(response: 0.5, dampingFraction: 0.82) }
}

extension ImprovementPillar {
    var gradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var accentColor: Color { gradientColors[0] }

    var designSymbol: String {
        switch self {
        case .physical: return "figure.strengthtraining.traditional"
        case .sport: return "trophy.fill"
        case .nutrition: return "fork.knife"
        case .learning: return "book.fill"
        case .life: return "heart.fill"
        }
    }

    private var gradientColors: [Color] {
        switch self {
        case .physical: return [.blue, .teal]
        case .sport: return [.orange, .red]
        case .nutrition: return [.green, .mint]
        case .learning: return [.indigo, .purple]
        case .life: return [.pink, .purple]
        }
    }
}

struct SignatureProgressRing: View {
    let fraction: Double
    var gradient: LinearGradient = ImprovementPillar.learning.gradient
    var lineWidth: CGFloat = 14
    var diameter: CGFloat = 148

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction = 0.0

    private var safeFraction: Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if !reduceMotion {
                Circle()
                    .trim(from: max(0, animatedFraction - 0.018), to: animatedFraction)
                    .stroke(
                        gradient,
                        style: StrokeStyle(lineWidth: lineWidth + 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 8)
                    .opacity(0.35)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion {
                animatedFraction = safeFraction
            } else {
                withAnimation(.lifeOSReveal.delay(0.08)) { animatedFraction = safeFraction }
            }
        }
        .onChange(of: safeFraction) { _, newValue in
            if reduceMotion {
                animatedFraction = newValue
            } else {
                withAnimation(.lifeOSReveal) { animatedFraction = newValue }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((safeFraction * 100).rounded())) percent")
    }
}
