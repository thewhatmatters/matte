import AppKit
import ApplicationServices

/// Thin, typed wrapper over the handful of Accessibility calls this app needs.
enum AX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (copy(element, attribute) as? NSNumber)?.boolValue ?? false
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let value = copy(element, attribute) else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    /// Window frame in Accessibility coordinates (top-left origin, +Y down).
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let positionValue = axValue(window, kAXPositionAttribute),
              let sizeValue = axValue(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setFrame(_ window: AXUIElement, _ rect: CGRect) -> Bool {
        var origin = rect.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

        // Size → position → size again: apps with size constraints frequently
        // reject the first pass, and a few reposition themselves on resize.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return result == .success
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// Accessibility uses a flipped, primary-screen-anchored coordinate space while
/// AppKit uses a bottom-left origin. Everything in the engine converts through here.
enum Coordinates {
    static var flipHeight: CGFloat {
        // NSScreen.screens[0] is always the screen containing the origin.
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func toAppKit(_ rect: CGRect) -> CGRect {
        Geometry.flip(rect, mainScreenMaxY: flipHeight)
    }

    static func toAccessibility(_ rect: CGRect) -> CGRect {
        Geometry.flip(rect, mainScreenMaxY: flipHeight)
    }
}
