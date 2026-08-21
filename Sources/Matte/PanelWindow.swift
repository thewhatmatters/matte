import AppKit
import Combine
import SwiftUI

/// NSPopover's arrow, corner radius and material are not public API, so a
/// custom-looking panel means owning the window. A non-activating NSPanel can
/// still take key focus for text editing without activating the whole app.
final class PanelWindow: NSPanel {
    /// Screen Y the panel hangs from. An NSWindow resizes around its bottom-left
    /// origin, so every height change would otherwise move the top edge — the
    /// panel appears to jump rather than grow downward. Re-anchoring inside
    /// `setFrame` makes the correction part of the same operation; doing it
    /// afterwards from a resize notification is always at least a frame late.
    var pinnedTopY: CGFloat?

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if let pinnedTopY {
            rect.origin.y = pinnedTopY - rect.height
        }
        super.setFrame(rect, display: flag)
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 554, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // The shadow is drawn in SwiftUI; see Theme.shadowPad.
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        // The design is a fixed dark surface; don't let light mode tint it.
        appearance = NSAppearance(named: .darkAqua)
    }

    // Needed so text fields inside the panel can be edited.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Heights SwiftUI measures for the controller. The drawer's space is reserved
/// in the window permanently, so opening it never resizes the window — an
/// NSHostingController reports its final preferredContentSize immediately, so a
/// window driven from it snaps to the new height in one step while the content
/// animates inside it.
final class PanelMetrics: ObservableObject {
    static let shared = PanelMetrics()
    /// Everything except the drawer, so this is unaffected by the animation.
    @Published var chromeHeight: CGFloat = 0
    @Published var drawerHeight: CGFloat = 0
    /// When the Never-resize combobox is open, Escape dismisses it rather than
    /// the whole panel.
    @Published var comboboxOpen = false
    /// Panel-coordinate frames for the combobox, converted to window space
    /// when deciding whether a click landed inside it.
    var comboboxFieldPanelRect = CGRect.zero
    var comboboxMenuPanelRect = CGRect.zero

    /// What the window reserves: constant whether the drawer is open or not.
    var reservedHeight: CGFloat { chromeHeight + drawerHeight }

    /// What is actually visible right now — used for hit testing, since the
    /// window extends past the panel.
    var panelHeight: CGFloat {
        chromeHeight + (Settings.shared.showSettingsSection ? drawerHeight : 0)
    }
    private init() {}
}

/// Clicks below the panel must reach whatever is behind it: the window is sized
/// for the drawer even when it is closed, so part of it is transparent.
final class PanelContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let pad = Theme.current.shadowPad
        let panel = NSRect(x: pad,
                           y: bounds.maxY - pad - PanelMetrics.shared.panelHeight,
                           width: Theme.current.width,
                           height: PanelMetrics.shared.panelHeight)
        guard panel.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// Root of the panel: the content plus the design's corner radius and hairline.
/// The window itself is transparent, so this view is the entire visible surface.
/// The panel itself, at its natural height. `--render` and `--uicheck` measure
/// this rather than the window wrapper around it.
struct PanelSurface: View {
    private let theme = Theme.current

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.panelRadius, style: .continuous)
        SettingsView()
            .background(theme.panelFill)
            .clipShape(shape)
            .overlay { shape.stroke(theme.hairline, lineWidth: 1) }
    }
}

struct PanelRoot: View {
    @ObservedObject private var metrics = PanelMetrics.shared
    private let theme = Theme.current

    var body: some View {
        VStack(spacing: 0) {
            PanelSurface()
                .shadow(color: .black.opacity(0.42), radius: 18, y: 10)
            Spacer(minLength: 0)
        }
        .padding(theme.shadowPad)
        // Fixed: the drawer changes the panel's height inside this frame, never
        // the frame itself. Any height that reaches AppKit is applied in one
        // step rather than interpolated, which is what made the panel jump.
        // Before the first measurement — and in --render / --uicheck, which
        // never run the window — fall back to laying out naturally.
        .frame(width: theme.width + theme.shadowPad * 2,
               height: metrics.reservedHeight > 0
                   ? metrics.reservedHeight + theme.shadowPad * 2 : nil,
               alignment: .top)
    }
}

/// Shows and positions the panel under the status item, and owns dismissal.
final class PanelController {
    private var window: PanelWindow?
    private var hosting: NSHostingView<PanelRoot>?
    private var metricsObserver: AnyCancellable?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Anchor to apply once the entry animation has finished — pinning during
    /// it would undo the 6pt rise on the first frame.
    private var pendingTopAnchor: CGFloat = 0

    var isVisible: Bool { window?.isVisible ?? false }
    var onClose: (() -> Void)?

    func toggle(from button: NSStatusBarButton) {
        isVisible ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        let window = window ?? makeWindow()
        self.window = window
        // Reset is offered against the state the panel opened in.
        Settings.shared.captureBaselines()

        // Size before positioning: the drawer's height is reserved whether it
        // is open or not, and preference callbacks land a runloop turn later, so
        // fall back to the laid-out size on the very first show.
        hosting?.layoutSubtreeIfNeeded()
        window.pinnedTopY = nil
        window.setContentSize(Self.windowSize)

        position(window, under: button)

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        let landed = window.frame
        window.setFrameOrigin(NSPoint(x: landed.origin.x, y: landed.origin.y + 6))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrameOrigin(landed.origin)
        } completionHandler: { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            window.setFrameOrigin(landed.origin)
            window.pinnedTopY = self.pendingTopAnchor
        }

        installMonitors()
    }

    func close() {
        PanelMetrics.shared.comboboxOpen = false
        removeMonitors()
        window?.pinnedTopY = nil
        guard let window, window.isVisible else { onClose?(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.onClose?()
        }
    }

    // MARK: - Plumbing

    private func makeWindow() -> PanelWindow {
        let window = PanelWindow()
        let container = PanelContainerView(frame: .zero)
        let hosting = NSHostingView(rootView: PanelRoot())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        // No bottom constraint: the panel takes its intrinsic height and hangs
        // from the top of the window, so the drawer animates inside a window
        // whose size never changes.
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        window.contentView = container
        self.hosting = hosting

        metricsObserver = PanelMetrics.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizeToMetrics() }

        return window
    }

    /// The window reserves the drawer's height whether it is open or not, so
    /// this only fires when the rest of the layout changes.
    private static var windowSize: NSSize {
        let pad = Theme.current.shadowPad
        return NSSize(width: Theme.current.width + pad * 2,
                      height: max(PanelMetrics.shared.reservedHeight, 1) + pad * 2)
    }

    /// Only fires when the layout outside the drawer changes — the drawer's
    /// own height is reserved either way.
    private func resizeToMetrics() {
        guard let window, window.isVisible else { return }
        let size = Self.windowSize
        guard size.height > 1, abs(window.frame.height - size.height) > 0.5 else { return }
        var frame = window.frame
        let top = window.pinnedTopY ?? frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        window.setFrame(frame, display: true, animate: false)
    }

    private func position(_ window: PanelWindow, under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = window.frame.size
        let pad = Theme.current.shadowPad

        // Position the visible panel, then offset for the shadow margin the
        // window carries around it.
        var x = anchor.midX - Theme.current.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - Theme.current.width - 8)
        var top = anchor.minY - 6
        if top - PanelMetrics.shared.panelHeight < visible.minY + 8 { top = anchor.maxY + 6 }

        let windowTop = (top + pad).rounded()
        window.pinnedTopY = nil
        window.setFrameOrigin(NSPoint(x: (x - pad).rounded(), y: windowTop - size.height))
        pendingTopAnchor = windowTop
    }

    private func installMonitors() {
        removeMonitors()
        // Global monitors never see this app's own events, so clicks inside the
        // panel don't dismiss it.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let metrics = PanelMetrics.shared
            if event.type == .keyDown, event.keyCode == 53 {   // Escape
                if metrics.comboboxOpen {
                    metrics.comboboxOpen = false
                    return nil
                }
                self?.close()
                return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown,
               metrics.comboboxOpen,
               self?.comboboxContains(event.locationInWindow) != true {
                metrics.comboboxOpen = false
            }
            return event
        }
    }

    /// Combobox frames are in SettingsView space (origin at the panel's
    /// top-left). The hosting view is padded by `shadowPad` and flipped, so
    /// convert through it rather than guessing window coordinates.
    private func comboboxContains(_ windowPoint: NSPoint) -> Bool {
        let field = windowRect(fromPanel: PanelMetrics.shared.comboboxFieldPanelRect)
        let menu = windowRect(fromPanel: PanelMetrics.shared.comboboxMenuPanelRect)
        var hit = field
        if menu.width > 0 { hit = hit.union(menu) }
        return hit.insetBy(dx: -4, dy: -4).contains(windowPoint)
    }

    private func windowRect(fromPanel rect: CGRect) -> CGRect {
        guard let hosting, rect.width > 0, rect.height > 0 else { return .null }
        let pad = Theme.current.shadowPad
        let local = NSRect(x: pad + rect.minX,
                           y: pad + rect.minY,
                           width: rect.width,
                           height: rect.height)
        return hosting.convert(local, to: nil)
    }

    private func removeMonitors() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
    }
}
