//
//  LifeOSColors.swift
//  LifeOS
//
//  Semantic color roles. Feature views should reach for `LOStatus` /
//  `Color.lifeOS*` instead of raw `.red`/`.green`/etc, so status meaning stays
//  consistent everywhere and isn't re-decided screen by screen. This is
//  layered on top of `ColorToken` (still the source of truth for
//  user-chosen Area/Profile brand colors) — status colors are for meaning,
//  ColorToken is for identity, and the two are never substituted for one
//  another.
//

import SwiftUI

/// The six status meanings used throughout LifeOS. Color alone never carries
/// the meaning — every use pairs the color with `symbol` and/or `label`.
enum LOStatus: Equatable {
    case attention   // needs attention / clearly behind
    case inProgress  // in progress / watch
    case complete    // completed / on track
    case focus       // focus / time / active
    case recovery    // recovery / rest context
    case neutral     // no data / not started

    var color: Color {
        switch self {
        case .attention: return .lifeOSAttention
        case .inProgress: return .lifeOSWatch
        case .complete: return .lifeOSOnTrack
        case .focus: return .lifeOSFocus
        case .recovery: return .lifeOSRecovery
        case .neutral: return .lifeOSNeutral
        }
    }

    var symbol: String {
        switch self {
        case .attention: return "exclamationmark.circle.fill"
        case .inProgress: return "circle.dashed"
        case .complete: return "checkmark.circle.fill"
        case .focus: return "bolt.fill"
        case .recovery: return "moon.fill"
        case .neutral: return "minus.circle"
        }
    }

    var label: String {
        switch self {
        case .attention: return "Needs attention"
        case .inProgress: return "In progress"
        case .complete: return "On track"
        case .focus: return "Active"
        case .recovery: return "Recovery"
        case .neutral: return "No data"
        }
    }
}

extension Color {
    /// The application accent. It is deliberately a deep oxblood rather than
    /// the default iOS blue, so actions feel considered without competing
    /// with a user's Area color.
    static let lifeOSAccent = Color(red: 0.40, green: 0.07, blue: 0.12)

    /// Warm parchment background used by the rebuilt product shell.
    static let lifeOSCanvas = Color(red: 0.97, green: 0.95, blue: 0.90)

    // Semantic colors remain distinct from identity colors. These muted
    // values retain their meaning while belonging to the same warm palette.
    static let lifeOSAttention = Color(red: 0.69, green: 0.20, blue: 0.17)
    static let lifeOSWatch = Color(red: 0.69, green: 0.39, blue: 0.10)
    static let lifeOSOnTrack = Color(red: 0.22, green: 0.45, blue: 0.31)
    static let lifeOSFocus = Color(red: 0.40, green: 0.07, blue: 0.12)
    static let lifeOSRecovery = Color(red: 0.40, green: 0.29, blue: 0.53)
    static let lifeOSNeutral = Color(red: 0.43, green: 0.42, blue: 0.39)

    /// Card/tile surface that separates clearly from the grouped background
    /// in both light and dark mode, without relying on a heavy material.
    static var lifeOSSurface: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor(red: 1.0, green: 0.99, blue: 0.96, alpha: 1)
        })
    }
}
