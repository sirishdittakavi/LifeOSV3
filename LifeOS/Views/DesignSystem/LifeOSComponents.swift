//
//  LifeOSComponents.swift
//  LifeOS
//
//  Small, composable building blocks shared across screens. Each `LO*` type
//  owns exactly one piece of UI (a card shell, a row, a chip, a button) and
//  is built from the existing tokens in LifeOSColors/LifeOSTypography/
//  Views/DesignSystem.swift — no screen should redeclare card padding,
//  status colors, elevation, or button styling locally.
//
//  Elevation model: every surface here gets a hairline stroke plus a soft,
//  color-matched shadow instead of a flat fill. That's what reads as
//  "premium" in the reference mockups — a plain background color alone
//  looks flat side by side with them, regardless of corner radius.
//

import SwiftUI

// MARK: - Elevation

/// The shared card elevation treatment: a barely-there stroke to define the
/// edge crisply in both themes, plus a soft directional shadow for depth.
/// Centralized so every card/tile/row lifts off the background the same way.
private struct LOElevation: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color = .lifeOSAccent
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color.lifeOSSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.10 : 0.9),
                                tint.opacity(colorScheme == .dark ? 0.08 : 0.05)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.32 : 0.08),
                radius: colorScheme == .dark ? 14 : 10, x: 0, y: 6
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.16 : 0.04),
                radius: 2, x: 0, y: 1
            )
    }
}

extension View {
    /// Applies the shared LifeOS elevation treatment (stroke + soft shadow).
    func lifeOSElevated(cornerRadius: CGFloat = LifeOSRadius.md, tint: Color = .lifeOSAccent) -> some View {
        modifier(LOElevation(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - LOIconBadge

/// The filled, tinted circle every icon sits in across the reference
/// mockups (baseball's red badge, protein's green badge, ...) — color is
/// always reinforced by the SF Symbol inside it, never a bare tint.
struct LOIconBadge: View {
    let symbol: String
    var tint: Color = LOStatus.neutral.color
    var diameter: CGFloat = 40

    /// Status-meaning badge (Today rows, task status) — color carries a
    /// semantic status.
    init(symbol: String, status: LOStatus, diameter: CGFloat = 40) {
        self.symbol = symbol
        self.tint = status.color
        self.diameter = diameter
    }

    /// Brand-identity badge (an Area/Profile's own `colorToken`) — color
    /// carries identity, not status, so it takes a raw `Color` instead of
    /// `LOStatus` to avoid implying a status meaning that isn't there.
    init(symbol: String, tint: Color, diameter: CGFloat = 40) {
        self.symbol = symbol
        self.tint = tint
        self.diameter = diameter
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.44, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - LOCard

/// The one card shell every screen uses. Clearly separates from the grouped
/// background in both light and dark mode via `lifeOSElevated`, not just a
/// flat fill.
struct LOCard<Content: View>: View {
    var padding: CGFloat = LifeOSSpacing.lg
    var tint: Color = .lifeOSAccent
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .lifeOSElevated(cornerRadius: LifeOSRadius.md, tint: tint)
    }
}

// MARK: - LOSectionHeader

/// Section heading with an optional trailing action ("View All", "Edit").
struct LOSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.lifeOSSectionTitle)
                .foregroundStyle(.primary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.lifeOSSecondary.weight(.semibold))
                    .foregroundStyle(Color.lifeOSAccent)
            }
        }
    }
}

// MARK: - LOHorizonPill

/// A progress percentage paired with its time horizon as a single compact
/// pill ("This week", "Today") — never a bare "67%". Used anywhere a
/// percentage could otherwise be mistaken for today's completion.
struct LOHorizonPill: View {
    let horizon: String
    var status: LOStatus = .focus

    var body: some View {
        Text(horizon)
            .font(.caption.weight(.bold))
            .foregroundStyle(status.color)
            .padding(.horizontal, LifeOSSpacing.sm + 2)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().stroke(status.color.opacity(0.22), lineWidth: 0.75)
            }
    }
}

// MARK: - LOMetricTile

/// A single at-a-glance metric — value, unit, label, status. Used for Home's
/// quick-glance grid (Protein, Water, Steps, ...) and for headline
/// measurements inside an Area hub.
struct LOMetricTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var caption: String? = nil
    var status: LOStatus = .neutral
    var symbol: String
    var action: (() -> Void)? = nil

    var body: some View {
        let tile = VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            HStack {
                LOIconBadge(symbol: symbol, status: status, diameter: 34)
                Spacer()
            }
            Text(title)
                .font(.lifeOSSecondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.lifeOSValueEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.lifeOSSecondary)
                        .foregroundStyle(.secondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LifeOSSpacing.md)
        .lifeOSElevated(cornerRadius: LifeOSRadius.sm, tint: status.color)

        if let action {
            Button(action: action) { tile }
                .buttonStyle(LOScalePressStyle())
        } else {
            tile
        }
    }
}

// MARK: - LOStatusControl

/// The tappable status affordance in a task row: an empty ring that becomes
/// a filled checkmark, or an explicit in-progress/skipped glyph. Never
/// color-only — always paired with an SF Symbol.
struct LOStatusControl: View {
    let status: LOStatus
    /// The drawn circle's diameter — purely visual. When `action` is set,
    /// the actual tap target is still guaranteed to be at least 44×44pt
    /// regardless of this value, so a visually-quiet small glyph never
    /// ships an under-sized hit area.
    var size: CGFloat = 30
    var action: (() -> Void)? = nil

    private var glyph: some View {
        ZStack {
            Circle()
                .fill(status == .neutral ? Color.primary.opacity(0.06) : status.color.opacity(0.16))
            Image(systemName: status == .neutral ? "circle" : status.symbol)
                .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                .foregroundStyle(status == .neutral ? Color.secondary.opacity(0.6) : status.color)
        }
        .frame(width: size, height: size)
    }

    var body: some View {
        if let action {
            Button(action: action) { glyph }
                .buttonStyle(LOScalePressStyle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(status.label)
        } else {
            glyph.accessibilityLabel(status.label)
        }
    }
}

// MARK: - LOTaskRow

/// Standard Today row: title, time/subtitle, status control. Tap opens
/// detail; tapping the status control drives Start/Finish/Skip directly.
struct LOTaskRow: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var status: LOStatus = .neutral
    var onTap: (() -> Void)? = nil
    var onStatusTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: LifeOSSpacing.md) {
            if let symbol {
                LOIconBadge(symbol: symbol, status: status)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.lifeOSCardTitle)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.lifeOSSecondary)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: LifeOSSpacing.sm)
            LOStatusControl(status: status, action: onStatusTap)
        }
        .padding(LifeOSSpacing.md)
        .lifeOSElevated(cornerRadius: LifeOSRadius.sm, tint: status.color)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - LOProgressBar

/// Horizontal current/target bar for a single measurement — never blended
/// across measurements or units. Fill uses a soft gradient rather than a
/// flat tint, matching the ring and hero treatments.
struct LOProgressBar: View {
    let label: String
    let currentText: String
    let targetText: String
    let fraction: Double
    var status: LOStatus = .inProgress

    private var safeFraction: Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.xs) {
            HStack {
                Text(label)
                    .font(.lifeOSBody.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(currentText) / \(targetText)")
                    .font(.lifeOSSecondary.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [status.color, status.color.opacity(0.65)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * safeFraction)
                        .shadow(color: status.color.opacity(0.35), radius: 3, x: 0, y: 1)
                }
            }
            .frame(height: 9)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - LOProgressRing

/// Standardized ring: wraps `SignatureProgressRing` with a semantic status
/// color instead of an arbitrary pillar gradient, plus optional center content.
struct LOProgressRing<Center: View>: View {
    let fraction: Double
    var status: LOStatus = .focus
    var diameter: CGFloat = 148
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            SignatureProgressRing(
                fraction: fraction,
                gradient: LinearGradient(colors: [status.color, status.color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: lineWidth,
                diameter: diameter
            )
            center()
        }
    }
}

extension LOProgressRing where Center == EmptyView {
    init(fraction: Double, status: LOStatus = .focus, diameter: CGFloat = 148, lineWidth: CGFloat = 14) {
        self.init(fraction: fraction, status: status, diameter: diameter, lineWidth: lineWidth) { EmptyView() }
    }
}

// MARK: - LOChip

/// Selectable chip — for template pickers, unit pickers, quick-add options.
/// Prefer this over free-text fields wherever the option set is known.
struct LOChip: View {
    let title: String
    var symbol: String? = nil
    var isSelected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.caption.weight(.semibold))
                }
                Text(title).font(.lifeOSSecondary.weight(.semibold))
            }
            .padding(.horizontal, LifeOSSpacing.md)
            .padding(.vertical, LifeOSSpacing.sm)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(colors: [Color.lifeOSAccent, Color.lifeOSAccent.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.lifeOSSurface)
                )
            }
            .overlay {
                Capsule().stroke(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: isSelected ? Color.lifeOSAccent.opacity(0.35) : .clear, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(LOScalePressStyle())
    }
}

// MARK: - LOPrimaryButton

/// The one primary call-to-action button style, wrapping the existing
/// `LifeOSPrimaryButtonStyle` so screens never restyle their own "Save"/"Done".
struct LOPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .buttonStyle(LifeOSPrimaryButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

/// Shared press feedback for tappable custom controls — a gentle scale-down,
/// matching `.lifeOSTap`, so every tappable badge/chip/tile feels the same.
struct LOScalePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.lifeOSTap, value: configuration.isPressed)
    }
}

// MARK: - LOQuickEntrySheet

/// Scaffold for small, focused entry sheets (finish-with-measurements,
/// quick-add) — a title, Cancel/Save toolbar, and freeform content, so
/// every quick sheet in the app looks and behaves the same way.
struct LOQuickEntrySheet<Content: View>: View {
    let title: String
    var saveTitle: String = "Done"
    var isSaveDisabled: Bool = false
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            Form {
                content()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle, action: onSave)
                        .fontWeight(.semibold)
                        .disabled(isSaveDisabled)
                }
            }
        }
    }
}
