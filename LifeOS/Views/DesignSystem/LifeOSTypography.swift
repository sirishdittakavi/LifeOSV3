//
//  LifeOSTypography.swift
//  LifeOS
//
//  Native SF type ramp shared by every screen, so hierarchy reads the same
//  everywhere and no view invents its own font sizes. Built on relative
//  text styles (`.largeTitle`, `.title2`, `.headline`, ...), never a fixed
//  `size:` point value, so every token scales under Dynamic Type.
//

import SwiftUI

extension Font {
    /// Screen title, e.g. "Baseball", "Today". 28–32 semibold.
    static var lifeOSScreenTitle: Font { .system(.title, design: .rounded).weight(.semibold) }

    /// The single hero number on a screen, e.g. a headline metric or ring center.
    /// Uses the relative `.largeTitle` text style (not a fixed point size) so
    /// it actually scales under Dynamic Type — a fixed `size:` value silently
    /// ignores the user's text-size setting, which a hero number shouldn't.
    static var lifeOSHeroMetric: Font { .system(.largeTitle, design: .rounded).weight(.semibold) }

    /// Section heading inside a screen, e.g. "Today", "Progress". 20–22 semibold.
    static var lifeOSSectionTitle: Font { .title3.weight(.semibold) }

    /// A value that matters at a glance but isn't the hero, e.g. a metric tile value. 18–22 semibold.
    /// Rounded design, like the hero metric, so every prominent number in the
    /// app reads as part of the same friendly numeral family.
    static var lifeOSValueEmphasis: Font { .system(.title2, design: .rounded).weight(.semibold) }

    /// Card/row title. 16–18 semibold.
    static var lifeOSCardTitle: Font { .headline.weight(.semibold) }

    /// Standard body text. 15–17 regular.
    static var lifeOSBody: Font { .body }

    /// Secondary/caption text — timestamps, units, helper copy. Medium weight,
    /// never below system `.caption`, to avoid the "tiny low-contrast text" trap.
    static var lifeOSSecondary: Font { .subheadline.weight(.medium) }
}

extension Text {
    /// Secondary text rendered with reduced-but-still-legible contrast.
    /// Use instead of `.foregroundStyle(.secondary)` + a raw small font.
    func lifeOSSecondaryStyle() -> Text {
        font(.lifeOSSecondary)
    }
}
