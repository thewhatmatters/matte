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

    /// Tallest device across the connected screens — every tile reserves this
    /// much so the devices share a floor and the labels share a baseline.
    private var deviceSlotHeight: CGFloat {
        screens.map {
            DeviceChrome<EmptyView>.totalHeight(kind: DeviceKind.kind(for: $0),
                                                aspect: $0.frame.width / max($0.frame.height, 1),
                                                screenWidth: theme.tileWidth)
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
                            screenWidth: theme.tileWidth) {
            ZStack {
                if let wallpaper = Wallpaper.image(for: screen) {
                    Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.black
                }
                // The reserved margin, drawn to scale.
                GeometryReader { proxy in
                    let scale = proxy.size.width / max(screen.frame.width, 1)
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                        .padding(EdgeInsets(top: padding.top * scale,
                                            leading: padding.left * scale,
                                            bottom: padding.bottom * scale,
                                            trailing: padding.right * scale))
                        .opacity(padding.isEmpty ? 0 : 1)
                }
            }
        }
        .saturation(isSelected ? 1 : 0.85)
        .overlay(alignment: .top) {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: theme.tileWidth,
                           height: (theme.tileWidth / max(screen.frame.width / screen.frame.height, 0.1)).rounded())
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
