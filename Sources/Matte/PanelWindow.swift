import AppKit
import SwiftUI

/// NSPopover's arrow, corner radius and material are not public API, so a
/// custom-looking panel means owning the window. A non-activating NSPanel can
/// still take key focus for text editing without activating the whole app.
final class PanelWindow: NSPanel {
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
    private var controller: NSHostingController<PanelRoot>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resizeObserver: Any?
    /// Top edge the panel hangs from, so it grows downward when content changes.
    private var anchorTopY: CGFloat = 0

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

        controller?.view.layoutSubtreeIfNeeded()
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
        }

        installMonitors()
    }

    func close() {
        removeMonitors()
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
        let controller = NSHostingController(rootView: PanelRoot())
        // Lets the window track the SwiftUI content's height instead of clipping
        // it when a section appears or the padding mode changes.
        controller.sizingOptions = [.preferredContentSize]
        window.contentViewController = controller
        self.controller = controller

        // queue: nil delivers synchronously on the posting thread. Hopping to
        // the main queue would land the origin correction a frame late, and the
        // top edge visibly wobbles for the length of the resize animation.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: nil
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
        // display: false — the resize that triggered this already scheduled a
        // redraw, and forcing a second one mid-animation causes tearing.
        window.setFrame(frame, display: false, animate: false)
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
