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

    var body: some View {
        HStack(alignment: .top, spacing: theme.tileGap) {
            ForEach(screens, id: \.self) { screen in
                tile(screen)
            }
        }
        .padding(theme.headerPadding)
        .frame(maxWidth: .infinity)
    }

    private func tile(_ screen: NSScreen) -> some View {
        let key = Settings.key(for: screen)
        return VStack(spacing: 8) {
            thumbnail(screen)
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
        let shape = RoundedRectangle(cornerRadius: theme.tileRadius)
        let padding = paddingFor(screen)
        return ZStack {
            if let wallpaper = Wallpaper.image(for: screen) {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
            // The reserved margin, to scale.
            GeometryReader { proxy in
                let scale = proxy.size.width / max(screen.frame.width, 1)
                let inset = EdgeInsets(top: padding.top * scale,
                                       leading: padding.left * scale,
                                       bottom: padding.bottom * scale,
                                       trailing: padding.right * scale)
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                    .padding(inset)
                    .opacity(padding.isEmpty ? 0 : 1)
            }
        }
        .frame(width: theme.tileWidth, height: theme.tileHeight)
        .clipShape(shape)
        .overlay {
            shape.stroke(selectedKey == Settings.key(for: screen)
                         ? Color.white.opacity(0.9) : Color.white.opacity(0.08),
                         lineWidth: 1)
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
