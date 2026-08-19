import AppKit

/// Reads the user's Dock configuration so the app can pick sensible defaults
/// instead of making them guess a number.
enum DockInfo {
    enum Position: String {
        case bottom, left, right

        var edge: EdgePadding.Edge {
            switch self {
            case .bottom: return .bottom
            case .left: return .left
            case .right: return .right
            }
        }
    }

    private static var dockDefaults: UserDefaults? {
        UserDefaults(suiteName: "com.apple.dock")
    }

    static var position: Position {
        let raw = dockDefaults?.string(forKey: "orientation") ?? "bottom"
        return Position(rawValue: raw) ?? .bottom
    }

    static var isAutoHidden: Bool {
        dockDefaults?.bool(forKey: "autohide") ?? false
    }

    /// How much room macOS is already reserving for the Dock on this screen —
    /// zero when the Dock is auto-hidden or lives on another display.
    static func reservedSpace(on screen: NSScreen) -> CGFloat {
        switch position {
        case .bottom: return screen.visibleFrame.minY - screen.frame.minY
        case .left: return screen.visibleFrame.minX - screen.frame.minX
        case .right: return screen.frame.maxX - screen.visibleFrame.maxX
        }
    }

    /// Enough padding to clear the Dock with a small gap beside it.
    ///
    /// Padding is measured from the physical screen edge, so this has to cover
    /// the Dock's whole thickness rather than just add to it. The tile-size
    /// estimate is the fallback for an auto-hidden Dock, which reserves nothing.
    static func suggestedPadding(for screen: NSScreen) -> Double {
        let stored = dockDefaults?.double(forKey: "tilesize") ?? 0
        let tile = stored > 0 ? stored : 48
        let estimate = tile * 1.1 + 16
        let thickness = max(Double(reservedSpace(on: screen)), estimate)
        return (thickness + 12).rounded()
    }

    /// The screen macOS is currently reserving Dock space on.
    static func hostScreen() -> NSScreen? {
        NSScreen.screens
            .map { ($0, reservedSpace(on: $0)) }
            .filter { $0.1 > 2 }
            .max { $0.1 < $1.1 }?.0
    }

    static var summary: String {
        var parts = ["Dock on the \(position.rawValue)"]
        if isAutoHidden { parts.append("auto-hidden") }
        if let host = hostScreen() { parts.append(host.localizedName) }
        return parts.joined(separator: " · ")
    }
}
