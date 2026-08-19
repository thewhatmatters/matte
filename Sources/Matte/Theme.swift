import AppKit
import SwiftUI

/// Visual tokens, taken from the Paper design. One theme now — the struct stays
/// so a second is a data change rather than a refactor.
struct Theme {
    static let current = Theme()

    // Panel
    let width: CGFloat = 554
    let panelRadius: CGFloat = 12
    let panelFill = Color(hex: 0x232427)
    let divider = Color(hex: 0x2E3033)
    let hairline = Color.white.opacity(0.10)

    // Header
    let headerPadding: CGFloat = 16
    let tileGap: CGFloat = 24
    let tileWidth: CGFloat = 158
    let tileHeight: CGFloat = 89
    let tileRadius: CGFloat = 4
    let caretSize: CGFloat = 12
    let caretFill = Color(hex: 0x1F2022)

    // Sections
    let settingsFill = Color.black
    let footerFill = Color(hex: 0x1F2022)

    // Fields
    let fieldFill = Color(hex: 0x262626)
    let fieldBorder = Color(hex: 0x525252)
    let fieldRadius: CGFloat = 10
    let fieldHeight: CGFloat = 32

    // Slider
    let trackFill = Color(hex: 0x5A5E66)
    let trackActive = Color(hex: 0xEBEBEB)
    let knobFill = Color(hex: 0xEBEBEB)
    let knobSize: CGFloat = 20
    let trackHeight: CGFloat = 4

    // Buttons
    let buttonRadius: CGFloat = 8
    let buttonHeight: CGFloat = 28
    let ghostFill = Color(hex: 0x2A2B2E)
    let accent = Color(hex: 0x3D9AFF)
    let iconButtonActive = Color.white.opacity(0.10)

    // Text
    let textPrimary = Color(hex: 0xFAFAFA)
    let textDisplayName = Color.white
    let textSecondary = Color(hex: 0xA3A3A3)
    let textLabel = Color(hex: 0x6C6F75)
    let textOnAccent = Color.white
    let checkFill = Color(hex: 0xEBEBEB)
    let checkMark = Color(hex: 0x171717)

    // The design specifies Figtree, which is not a system font and is not
    // installed here. SF at the same metrics until it is vendored.
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
