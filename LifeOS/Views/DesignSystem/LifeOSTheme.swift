//
//  LifeOSTheme.swift
//  LifeOS
//
//  Small cross-cutting theme helpers that don't belong in Colors/Typography/
//  Components individually. Layout tokens (`LifeOSSpacing`, `LifeOSRadius`)
//  and motion (`Animation.lifeOSTap`/`.lifeOSReveal`) already live in
//  Views/DesignSystem.swift and are reused as-is, not duplicated here.
//

import SwiftUI

/// A progress percentage paired with the time horizon it's measured over —
/// "67% · This week", never a bare "67%" — so Progress numbers can never be
/// mistaken for today's completion.
struct LOProgressHeadline: View {
    let percent: Int
    let horizon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(percent)%")
                .font(.lifeOSHeroMetric)
                .foregroundStyle(.primary)
            Text(horizon)
                .font(.lifeOSSecondary)
                .foregroundStyle(.secondary)
        }
    }
}
