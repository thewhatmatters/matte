import AppKit
import SwiftUI

/// Visual tokens for the panel. Every custom control reads these rather than
/// hard-coding colour or metrics, so a theme swap is a data change.
struct Theme: Identifiable, Equatable {
    enum Appearance: Equatable { case fixedDark, followsSystem }
    enum Backdrop: Equatable {
        case vibrancy(NSVisualEffectView.Material)
        case solid
    }

    let id: String
    let name: String
    let blurb: String

    let appearance: Appearance
    let backdrop: Backdrop

    // Metrics
    let panelRadius: CGFloat
    let controlRadius: CGFloat
    let panelPadding: CGFloat
    let sectionSpacing: CGFloat
    let rowHeight: CGFloat

    // Surfaces
    let controlFill: Color
    let controlFillActive: Color
    let trackFill: Color
    let border: Color
    let dividerColor: Color
    /// Flat themes draw borders instead of fills.
    let prefersBorders: Bool

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let titleFont: Font
    let labelFont: Font
    let numeralFont: Font

    var accent: Color { Color(nsColor: .controlAccentColor) }

    static let all: [Theme] = [.darkHUD, .frosted, .flatMono]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .frosted
    }

    /// Fixed dark, translucent, high contrast — reads as a pro tool.
    static let darkHUD = Theme(
        id: "darkHUD",
        name: "Dark HUD",
        blurb: "Fixed dark, translucent, high contrast",
        appearance: .fixedDark,
        backdrop: .vibrancy(.hudWindow),
        panelRadius: 10,
        controlRadius: 6,
        panelPadding: 14,
        sectionSpacing: 12,
        rowHeight: 26,
        controlFill: Color.white.opacity(0.07),
        controlFillActive: Color.white.opacity(0.14),
        trackFill: Color.white.opacity(0.12),
        border: Color.white.opacity(0.10),
        dividerColor: Color.white.opacity(0.08),
        prefersBorders: false,
        textPrimary: Color.white,
        textSecondary: Color.white.opacity(0.55),
        titleFont: .system(size: 13, weight: .semibold),
        labelFont: .system(size: 11, weight: .regular),
        numeralFont: .system(size: 11, weight: .medium, design: .monospaced)
    )

    /// Follows system light/dark with real vibrancy and soft depth.
    static let frosted = Theme(
        id: "frosted",
        name: "Frosted",
        blurb: "Adaptive, vibrant, generous",
        appearance: .followsSystem,
        backdrop: .vibrancy(.popover),
        panelRadius: 12,
        controlRadius: 8,
        panelPadding: 16,
        sectionSpacing: 14,
        rowHeight: 28,
        controlFill: Color(nsColor: .quaternaryLabelColor).opacity(0.5),
        controlFillActive: Color(nsColor: .tertiaryLabelColor).opacity(0.5),
        trackFill: Color(nsColor: .quaternaryLabelColor),
        border: Color(nsColor: .separatorColor),
        dividerColor: Color(nsColor: .separatorColor),
        prefersBorders: false,
        textPrimary: Color(nsColor: .labelColor),
        textSecondary: Color(nsColor: .secondaryLabelColor),
        titleFont: .system(size: 13, weight: .semibold, design: .rounded),
        labelFont: .system(size: 11, weight: .regular, design: .rounded),
        numeralFont: .system(size: 11, weight: .medium, design: .rounded).monospacedDigit()
    )

    /// Near-flat, hairline borders, colour reserved for the active state.
    static let flatMono = Theme(
        id: "flatMono",
        name: "Flat",
        blurb: "Flat, hairline, dense",
        appearance: .followsSystem,
        backdrop: .solid,
        panelRadius: 8,
        controlRadius: 4,
        panelPadding: 12,
        sectionSpacing: 10,
        rowHeight: 24,
        controlFill: .clear,
        controlFillActive: Color(nsColor: .quaternaryLabelColor).opacity(0.4),
        trackFill: Color(nsColor: .quaternaryLabelColor).opacity(0.6),
        border: Color(nsColor: .separatorColor),
        dividerColor: Color(nsColor: .separatorColor),
        prefersBorders: true,
        textPrimary: Color(nsColor: .labelColor),
        textSecondary: Color(nsColor: .secondaryLabelColor),
        titleFont: .system(size: 12, weight: .semibold),
        labelFont: .system(size: 11, weight: .regular),
        numeralFont: .system(size: 11, weight: .regular, design: .monospaced)
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .frosted
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
