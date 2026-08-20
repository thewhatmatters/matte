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
        hasShadow = true
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
    var windowHeight: CGFloat { chromeHeight + drawerHeight }
    private init() {}
}

/// Clicks below the panel must reach whatever is behind it: the window is sized
/// for the drawer even when it is closed, so part of it is transparent.
final class PanelContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard let panel = subviews.first, panel.frame.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// Root of the panel: the content plus the design's corner radius and hairline.
/// The window itself is transparent, so this view is the entire visible surface.
struct PanelRoot: View {
    private let theme = Theme.current

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.panelRadius, style: .continuous)
        SettingsView()
            .background(theme.panelFill)
            .clipShape(shape)
            .overlay { shape.stroke(theme.hairline, lineWidth: 1) }
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
        let reserved = PanelMetrics.shared.windowHeight
        let laidOut = (hosting?.fittingSize.height ?? 0)
            + (Settings.shared.showSettingsSection ? 0 : PanelMetrics.shared.drawerHeight)
        window.pinnedTopY = nil
        window.setContentSize(NSSize(width: Theme.current.width, height: max(reserved, laidOut)))

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
    private func resizeToMetrics() {
        guard let window, window.isVisible else { return }
        let height = PanelMetrics.shared.windowHeight
        guard height > 1, abs(window.frame.height - height) > 0.5 else { return }
        var frame = window.frame
        let top = window.pinnedTopY ?? frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        window.setFrame(frame, display: true, animate: false)
        window.invalidateShadow()
    }

    private func position(_ window: PanelWindow, under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = window.frame.size

        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        var top = anchor.minY - 6
        if top - size.height < visible.minY + 8 { top = anchor.maxY + 6 + size.height }

        window.pinnedTopY = nil
        window.setFrameOrigin(NSPoint(x: x.rounded(), y: (top - size.height).rounded()))
        pendingTopAnchor = top.rounded()
    }

    private func installMonitors() {
        removeMonitors()
        // Global monitors never see this app's own events, so clicks inside the
        // panel don't dismiss it.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Escape
            self?.close()
            return nil
        }
    }

    private func removeMonitors() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
    }
}
