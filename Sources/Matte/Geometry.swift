import CoreGraphics

/// Pure geometry the engine depends on, kept free of AppKit state so it can be
/// exercised by `--selftest`.
enum Geometry {
    static let minimumWindowSize = CGSize(width: 200, height: 150)

    /// The area padding is measured from.
    ///
    /// Deliberately the physical screen, not `visibleFrame` — 16pt of padding
    /// should read as 16pt on every edge, rather than 16pt *plus* whatever the
    /// Dock happens to reserve. The menu bar is the one exception: nothing
    /// useful can live under it, so it stays carved out.
    static func contentBounds(frame: CGRect, visibleFrame: CGRect) -> CGRect {
        var bounds = frame
        let menuBar = frame.maxY - visibleFrame.maxY
        if menuBar > 0 { bounds.size.height -= menuBar }
        return bounds
    }

    static func paddedRect(frame: CGRect, visibleFrame: CGRect, padding: EdgePadding,
                           minimumSize: CGSize = minimumWindowSize) -> CGRect {
        var rect = contentBounds(frame: frame, visibleFrame: visibleFrame)
        rect.origin.x += padding.left
        rect.origin.y += padding.bottom
        rect.size.width -= (padding.left + padding.right)
        rect.size.height -= (padding.top + padding.bottom)
        // Never collapse a screen to nothing, however silly the padding is.
        rect.size.width = max(rect.size.width, minimumSize.width)
        rect.size.height = max(rect.size.height, minimumSize.height)
        return rect
    }

    /// Whether a window is filling its screen, and so should track the padded
    /// rect exactly — growing as well as shrinking when the padding changes.
    static func fillsScreen(_ rect: CGRect, bounds: CGRect, visibleFrame: CGRect,
                            tolerance: CGFloat = 12) -> Bool {
        rect.approximatelyEquals(bounds, tolerance: tolerance)
            || rect.approximatelyEquals(visibleFrame, tolerance: tolerance)
            || (rect.width >= bounds.width * 0.92 && rect.height >= bounds.height * 0.92)
    }

    /// A window still sitting on a rect this app previously applied is one it
    /// sized, even if the process has restarted since.
    static func matchesAppliedRect(_ rect: CGRect, history: [CGRect], tolerance: CGFloat = 8) -> Bool {
        history.contains { rect.approximatelyEquals($0, tolerance: tolerance) }
    }

    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    static func shouldClamp(_ rect: CGRect, bounds: CGRect, scope: WindowScope,
                            tolerance: CGFloat = 8) -> Bool {
        switch scope {
        case .allWindows:
            return true
        case .largeWindows:
            // Big windows only, and only ones actually parked on the screen — a
            // window the user deliberately dragged off the edge is left alone.
            let onScreen = bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(rect)
            let isLarge = rect.width >= bounds.width * 0.55 || rect.height >= bounds.height * 0.55
            return onScreen && isLarge
        }
    }

    /// Accessibility is top-left origin (+Y down) anchored to the main display;
    /// AppKit is bottom-left origin (+Y up). One global flip converts either way.
    static func flip(_ rect: CGRect, mainScreenMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x,
               y: mainScreenMaxY - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }
}

extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }

    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
