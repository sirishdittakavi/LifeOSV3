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
    static let lifeOSAttention = Color.red
    static let lifeOSWatch = Color.orange
    static let lifeOSOnTrack = Color.green
    static let lifeOSFocus = Color.blue
    static let lifeOSRecovery = Color.purple
    static let lifeOSNeutral = Color.gray

    /// Card/tile surface that separates clearly from the grouped background
    /// in both light and dark mode, without relying on a heavy material.
    static var lifeOSSurface: Color { Color(.secondarySystemGroupedBackground) }
}
