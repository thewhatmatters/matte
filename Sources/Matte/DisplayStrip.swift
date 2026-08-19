import AppKit
import SwiftUI

/// Desktop wallpapers, resolved per screen. `desktopImageURL` needs no
/// permission, so the tiles can show the real desktop.
enum Wallpaper {
    private static var cache: [String: NSImage] = [:]

    static func image(for screen: NSScreen) -> NSImage? {
        let key = Settings.key(for: screen)
        if let cached = cache[key] { return cached }
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[key] = image
        return image
    }

    static func invalidate() { cache.removeAll() }
}

/// The row of display tiles, mirroring System Settings' arrangement view.
struct DisplayStrip: View {
    private let theme = Theme.current
    let screens: [NSScreen]
    @Binding var selectedKey: String
    /// Drawn inside each thumbnail so the numbers below have a visible meaning.
    let paddingFor: (NSScreen) -> EdgePadding

    /// A thumbnail is roughly 4% of the real screen, so a realistic padding
    /// scales to under 3pt. Non-zero edges are floored at 1.5pt so "there is
    /// padding here" stays legible; above that the proportions are to scale.
    private static func previewInset(_ padding: EdgePadding,
                                     in size: CGSize, screen: CGSize) -> EdgeInsets {
        func band(_ value: Double, _ extent: CGFloat, _ screenExtent: CGFloat) -> CGFloat {
            value > 0 ? max(value * extent / max(screenExtent, 1), 1.5) : 0
        }
        return EdgeInsets(top: band(padding.top, size.height, screen.height),
                          leading: band(padding.left, size.width, screen.width),
                          bottom: band(padding.bottom, size.height, screen.height),
                          trailing: band(padding.right, size.width, screen.width))
    }

    /// Tallest device across the connected screens — every tile reserves this
    /// much so the devices share a floor and the labels share a baseline.
    private var deviceSlotHeight: CGFloat {
        screens.map {
            DeviceChrome<EmptyView>.totalHeight(kind: DeviceKind.kind(for: $0),
                                                aspect: $0.frame.width / max($0.frame.height, 1),
                                                screenWidth: theme.deviceWidth)
        }.max() ?? theme.tileHeight
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: theme.tileGap) {
            ForEach(screens, id: \.self) { screen in
                tile(screen)
            }
        }
        .padding(theme.headerPadding)
        .frame(maxWidth: .infinity)
    }

    private func tile(_ screen: NSScreen) -> some View {
        let key = Settings.key(for: screen)
        return VStack(spacing: 10) {
            thumbnail(screen)
                .frame(width: theme.tileWidth, height: deviceSlotHeight, alignment: .bottom)
            VStack(spacing: 4) {
                Text(primaryName(screen))
                    .font(theme.font(14))
                    .foregroundStyle(theme.textDisplayName)
                Text(secondaryName(screen))
                    .font(theme.font(12))
                    .foregroundStyle(theme.textSecondary)
            }
            .lineLimit(1)
            .frame(width: theme.tileWidth)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = key }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(key == selectedKey ? [.isSelected, .isButton] : .isButton)
    }

    private func thumbnail(_ screen: NSScreen) -> some View {
        let padding = paddingFor(screen)
        let isSelected = selectedKey == Settings.key(for: screen)
        return DeviceChrome(kind: DeviceKind.kind(for: screen),
                            aspect: screen.frame.width / max(screen.frame.height, 1),
                            screenWidth: theme.deviceWidth) {
            // Color.clear fixes the layout size; a `.fill` image inside a
            // ZStack inflates it, which pushed the margin rectangle's top and
            // bottom edges outside the clip so only its sides were visible.
            Color.clear
                .overlay {
                    if let wallpaper = Wallpaper.image(for: screen) {
                        Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.black
                    }
                }
                .clipped()
                .overlay {
                    GeometryReader { proxy in
                        let inset = Self.previewInset(padding, in: proxy.size, screen: screen.frame.size)
                        ZStack {
                            // The reserved margin is dimmed rather than outlined —
                            // an outline is indistinguishable from the selection ring.
                            Rectangle()
                                .fill(Color.black.opacity(0.62))
                                .mask {
                                    Rectangle()
                                        .overlay {
                                            Rectangle().padding(inset).blendMode(.destinationOut)
                                        }
                                        .compositingGroup()
                                }
                            Rectangle()
                                .strokeBorder(Color.white.opacity(0.75), lineWidth: 0.75)
                                .padding(inset)
                        }
                        .opacity(padding.isEmpty ? 0 : 1)
                    }
                }
        }
        .saturation(isSelected ? 1 : 0.85)
        .overlay(alignment: .top) {
            // Selection sits outside the device in the accent colour, the way
            // System Settings marks the selected display.
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accent, lineWidth: 2)
                    .frame(width: theme.deviceWidth,
                           height: (theme.deviceWidth / max(screen.frame.width / screen.frame.height, 0.1)).rounded())
                    .padding(-3)
            }
        }
    }

    /// One Mac, so the display's own name leads; the role goes underneath.
    private func primaryName(_ screen: NSScreen) -> String {
        screen.localizedName
    }

    private func secondaryName(_ screen: NSScreen) -> String {
        let isMain = screen == NSScreen.screens.first
        let size = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
        return isMain ? "Main Display · \(size)" : size
    }
}

/// The caret that points from the padding section up at the selected tile.
struct SelectionCaret: View {
    private let theme = Theme.current
    let offset: CGFloat

    var body: some View {
        Rectangle()
            .fill(theme.caretFill)
            .frame(width: theme.caretSize, height: theme.caretSize)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.divider).frame(height: 1)
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.divider).frame(width: 1)
            }
            .rotationEffect(.degrees(45))
            .frame(width: theme.caretSize, height: theme.caretSize / 2, alignment: .top)
            .clipped()
            .offset(x: offset, y: -theme.caretSize / 2)
    }
}
