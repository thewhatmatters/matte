import AppKit
import Combine

/// Padding in points reserved on each edge of a screen.
struct EdgePadding: Codable, Equatable {
    var top: Double = 0
    var bottom: Double = 0
    var left: Double = 0
    var right: Double = 0

    static let zero = EdgePadding()

    var isEmpty: Bool { top <= 0 && bottom <= 0 && left <= 0 && right <= 0 }

    subscript(edge: Edge) -> Double {
        get {
            switch edge {
            case .top: return top
            case .bottom: return bottom
            case .left: return left
            case .right: return right
            }
        }
        set {
            switch edge {
            case .top: top = newValue
            case .bottom: bottom = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    enum Edge: String, CaseIterable, Identifiable {
        case top, bottom, left, right
        var id: String { rawValue }
        /// Reading order for the four-up field row, matching CSS shorthand.
        static let displayOrder: [Edge] = [.top, .right, .bottom, .left]
        var label: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .top: return "arrow.up.to.line"
            case .bottom: return "arrow.down.to.line"
            case .left: return "arrow.left.to.line"
            case .right: return "arrow.right.to.line"
            }
        }
    }
}

enum WindowScope: String, CaseIterable, Identifiable {
    /// Windows that fill or half-fill the screen — the ones that actually cover the Dock.
    case largeWindows
    /// Keep every window inside the padded area.
    case allWindows

    var id: String { rawValue }
    var label: String {
        switch self {
        case .largeWindows: return "Large windows"
        case .allWindows: return "All windows"
        }
    }
    var help: String {
        switch self {
        case .largeWindows: return "Maximized and half-screen windows are pushed inside the padding. Small windows are left alone."
        case .allWindows: return "Every window is kept inside the padding."
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    static let maxPadding: Double = 400

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.isEnabled) } }
    @Published var windowScope: WindowScope { didSet { defaults.set(windowScope.rawValue, forKey: Key.windowScope) } }
    @Published var showOverlayOnChange: Bool { didSet { defaults.set(showOverlayOnChange, forKey: Key.overlay) } }
    /// Padded rects this app has applied, per display, most recent first.
    ///
    /// Window identity does not survive a relaunch, so this is how the engine
    /// recognises its own full windows afterwards: a window still sitting on a
    /// rect we previously applied is one we sized, and should be re-fitted.
    @Published var appliedRects: [String: [[Double]]] { didSet { persist(appliedRects, Key.appliedRects) } }
    /// Whether the expandable settings section is showing.
    @Published var showSettingsSection: Bool { didSet { defaults.set(showSettingsSection, forKey: Key.settingsSection) } }
    /// Whether the popover shows one slider for all edges or a field per edge.
    @Published var editEdgesIndividually: Bool { didSet { defaults.set(editEdgesIndividually, forKey: Key.individualEdges) } }
    /// Apps the engine never touches. Escape hatch for anything that fights back.
    @Published var excludedBundleIDs: [String] { didSet { defaults.set(excludedBundleIDs, forKey: Key.excluded) } }

    /// Padding used by any display without its own override.
    @Published var globalPadding: EdgePadding { didSet { persist(globalPadding, Key.globalPadding) } }
    /// Per-display overrides, keyed by `Settings.key(for:)`.
    @Published var overrides: [String: EdgePadding] { didSet { persist(overrides, Key.overrides) } }

    private enum Key {
        static let isEnabled = "isEnabled"
        static let windowScope = "windowScope"
        static let overlay = "showOverlayOnChange"
        static let globalPadding = "globalPadding"
        static let overrides = "displayOverrides"
        static let appliedRects = "appliedRects"
        static let settingsSection = "showSettingsSection"
        static let individualEdges = "editEdgesIndividually"
        static let excluded = "excludedBundleIDs"
        static let didFirstRun = "didFirstRun"
    }

    private init() {
        defaults.register(defaults: [Key.isEnabled: true, Key.overlay: true])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        windowScope = WindowScope(rawValue: defaults.string(forKey: Key.windowScope) ?? "") ?? .largeWindows
        showOverlayOnChange = defaults.bool(forKey: Key.overlay)
        appliedRects = Self.decode(defaults.data(forKey: Key.appliedRects)) ?? [:]
        showSettingsSection = defaults.bool(forKey: Key.settingsSection)
        editEdgesIndividually = defaults.bool(forKey: Key.individualEdges)
        excludedBundleIDs = defaults.stringArray(forKey: Key.excluded) ?? []
        globalPadding = Self.decode(defaults.data(forKey: Key.globalPadding)) ?? .zero
        overrides = Self.decode(defaults.data(forKey: Key.overrides)) ?? [:]

        if !defaults.bool(forKey: Key.didFirstRun) {
            defaults.set(true, forKey: Key.didFirstRun)
            seedFromDock()
        }
    }

    // MARK: - Lookup

    /// A key that survives relaunches and reconnects, unlike CGDirectDisplayID.
    static func key(for screen: NSScreen) -> String {
        "\(screen.localizedName)|\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    func padding(for screen: NSScreen) -> EdgePadding {
        overrides[Self.key(for: screen)] ?? globalPadding
    }

    func hasOverride(_ screen: NSScreen) -> Bool {
        overrides[Self.key(for: screen)] != nil
    }

    func setPadding(_ padding: EdgePadding, for screen: NSScreen?) {
        if let screen {
            overrides[Self.key(for: screen)] = padding
        } else {
            globalPadding = padding
        }
    }

    func clearOverride(for screen: NSScreen) {
        overrides.removeValue(forKey: Self.key(for: screen))
    }

    /// The display worth showing first: the one the Dock is on, if it has its
    /// own padding. Otherwise the "All displays" defaults.
    func initialEditingTarget() -> String? {
        guard let dockScreen = DockInfo.hostScreen(), hasOverride(dockScreen) else { return nil }
        return Self.key(for: dockScreen)
    }

    /// Keeps a short history per display — long enough to recognise a window
    /// across a few padding changes, short enough not to match everything.
    private static let appliedRectHistoryLimit = 8

    func recordAppliedRect(_ rect: CGRect, for screen: NSScreen) {
        let key = Self.key(for: screen)
        let entry = [rect.origin.x, rect.origin.y, rect.width, rect.height].map(Double.init)
        var history = appliedRects[key] ?? []
        guard history.first != entry else { return }
        history.removeAll { $0 == entry }
        history.insert(entry, at: 0)
        appliedRects[key] = Array(history.prefix(Self.appliedRectHistoryLimit))
    }

    func appliedRects(for screen: NSScreen) -> [CGRect] {
        (appliedRects[Self.key(for: screen)] ?? []).compactMap { values in
            guard values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
    }

    var hasAnyPadding: Bool {
        !globalPadding.isEmpty || overrides.values.contains { !$0.isEmpty }
    }

    // MARK: - First run

    /// Puts the initial padding on the edge where the Dock actually lives, and
    /// only on the display that hosts it.
    private func seedFromDock() {
        guard let dockScreen = DockInfo.hostScreen() ?? NSScreen.main else { return }
        var padding = EdgePadding.zero
        padding[DockInfo.position.edge] = DockInfo.suggestedPadding(for: dockScreen)
        overrides[Self.key(for: dockScreen)] = padding
    }

    // MARK: - Coding

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
