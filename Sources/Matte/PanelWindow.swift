import AppKit
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
        let controller = NSHostingController(rootView: PanelRoot())
        // Lets the window track the SwiftUI content's height instead of clipping
        // it when a section appears or the padding mode changes.
        controller.sizingOptions = [.preferredContentSize]
        window.contentViewController = controller
        self.controller = controller

        return window
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
