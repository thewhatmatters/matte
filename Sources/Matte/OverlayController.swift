import AppKit

/// Briefly outlines the padded region on each screen so the numbers in the
/// popover have a visible meaning.
final class OverlayController {
    static let shared = OverlayController()

    private var windows: [NSWindow] = []
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func flash(duration: TimeInterval = 1.1) {
        show()
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func show() {
        let rects = PaddingEngine.shared.paddedRects()
        if windows.count != rects.count {
            teardown()
            windows = rects.map { _ in makeWindow() }
        }
        for (window, entry) in zip(windows, rects) {
            window.setFrame(entry.screen.frame, display: false)
            if let view = window.contentView as? OverlayView {
                view.paddedRect = entry.rect.offsetBy(dx: -entry.screen.frame.minX, dy: -entry.screen.frame.minY)
                view.needsDisplay = true
            }
            window.orderFrontRegardless()
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        for window in windows {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        }
    }

    private func teardown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        // Above app windows but below the popover, so the settings UI stays legible.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.hasShadow = false
        window.alphaValue = 0
        window.contentView = OverlayView(frame: .zero)
        return window
    }
}

private final class OverlayView: NSView {
    var paddedRect: CGRect = .zero

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rounded = NSBezierPath(roundedRect: paddedRect, xRadius: 12, yRadius: 12)

        // Dim only the reserved margin, so the padding reads as a frame.
        let mask = NSBezierPath(rect: bounds)
        mask.append(rounded)
        mask.windingRule = .evenOdd
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        mask.fill()

        context.setLineWidth(2)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        rounded.stroke()
    }
}
