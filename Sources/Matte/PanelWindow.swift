import AppKit
import SwiftUI

/// NSPopover's arrow, corner radius and material are not public API, so a
/// custom-looking panel means owning the window. A non-activating NSPanel can
/// still take key focus for text editing without activating the whole app.
final class PanelWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
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
    }

    // Needed so text fields inside the panel can be edited.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// The window is transparent; this view is the panel's entire visible surface.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Backdrop, corner radius and hairline for the panel, driven by the theme.
struct PanelChrome<Content: View>: View {
    let theme: Theme
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.panelRadius, style: .continuous)
        content
            .background {
                switch theme.backdrop {
                case .vibrancy(let material): VisualEffectBackground(material: material)
                case .solid: Color(nsColor: .windowBackgroundColor)
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(theme.border, lineWidth: 1) }
    }
}

/// Root of the panel. Observing Settings here means a theme change re-renders
/// the chrome *and* the content without the controller replacing the root view
/// — which would reset the view's `@State` (selected display, focus).
struct PanelRoot: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        PanelChrome(theme: settings.theme) {
            SettingsView()
        }
    }
}

/// Shows and positions the panel under the status item, and owns dismissal.
final class PanelController {
    private var window: PanelWindow?
    private var controller: NSHostingController<PanelRoot>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resizeObserver: Any?
    /// Top edge the panel hangs from, so it grows downward when content changes.
    private var anchorTopY: CGFloat = 0

    var isVisible: Bool { window?.isVisible ?? false }
    var onClose: (() -> Void)?

    func toggle(from button: NSStatusBarButton, theme: Theme) {
        isVisible ? close() : show(from: button, theme: theme)
    }

    func show(from button: NSStatusBarButton, theme: Theme) {
        let window = window ?? makeWindow()
        self.window = window
        applyAppearance(theme)

        controller?.view.layoutSubtreeIfNeeded()
        position(window, under: button)
        window.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close() {
        removeMonitors()
        window?.orderOut(nil)
        onClose?()
    }

    /// Only the window-level appearance needs updating on a theme change; the
    /// SwiftUI tree redraws itself.
    func applyAppearance(_ theme: Theme) {
        window?.appearance = theme.appearance == .fixedDark
            ? NSAppearance(named: .darkAqua)
            : nil
    }

    // MARK: - Plumbing

    private func makeWindow() -> PanelWindow {
        let window = PanelWindow()
        let controller = NSHostingController(rootView: PanelRoot())
        // Lets the window track the SwiftUI content's height instead of clipping
        // it when a section appears or the padding mode changes.
        controller.sizingOptions = [.preferredContentSize]
        window.contentViewController = controller
        self.controller = controller

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.pinTopEdge()
        }
        return window
    }

    /// A window grows from its bottom-left origin, which would push the panel up
    /// through the menu bar. Re-pin the top after every resize.
    private func pinTopEdge() {
        guard let window, window.isVisible, anchorTopY > 0 else { return }
        var frame = window.frame
        let desired = anchorTopY - frame.height
        guard abs(frame.origin.y - desired) > 0.5 else { return }
        frame.origin.y = desired
        window.setFrame(frame, display: true, animate: false)
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

        anchorTopY = top.rounded()
        window.setFrameOrigin(NSPoint(x: x.rounded(), y: (top - size.height).rounded()))
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
