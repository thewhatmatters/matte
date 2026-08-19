import AppKit
import IOKit.ps
import SwiftUI

/// Which physical device a screen belongs to, so the tile can draw the right
/// silhouette — the way System Settings' arrangement view does.
enum DeviceKind {
    case laptop
    case iMac
    case desktopDisplay

    /// `CGDisplayIsBuiltin` is public, unlike the imagery System Settings uses.
    static func kind(for screen: NSScreen) -> DeviceKind {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0 else {
            return .desktopDisplay
        }
        return hasInternalBattery ? .laptop : .iMac
    }

    /// Apple Silicon reports `hw.model` as "Mac16,6" — no "MacBook" to match on.
    /// An internal battery is the reliable laptop signal.
    private static let hasInternalBattery: Bool = {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { return false }
            return description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType
        }
    }()
}

/// A screen drawn inside its device: bezel, notch and stand. `content` is the
/// live desktop, clipped to the panel area.
struct DeviceChrome<Content: View>: View {
    let kind: DeviceKind
    let aspect: CGFloat
    let screenWidth: CGFloat
    @ViewBuilder let content: Content

    private let bezel = Color(hex: 0x1B1C1E)
    private let metal = Color(hex: 0xA9ADB4)
    private let metalDark = Color(hex: 0x74787E)

    var body: some View {
        VStack(spacing: 0) {
            panel
            stand
        }
    }

    /// Full drawn height, so the strip can bottom-align mixed device types.
    static func totalHeight(kind: DeviceKind, aspect: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let screen = (screenWidth / max(aspect, 0.1)).rounded()
        switch kind {
        case .laptop: return screen + 5
        case .iMac: return screen + max(screen * 0.08, 5) + screen * 0.14 + 3.5
        case .desktopDisplay: return screen + screen * 0.16 + 4
        }
    }

    private var screenHeight: CGFloat { (screenWidth / max(aspect, 0.1)).rounded() }

    private var panel: some View {
        let outer = RoundedRectangle(cornerRadius: kind == .laptop ? 6 : 5, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: kind == .laptop ? 3 : 2, style: .continuous)
        return outer
            .fill(bezel)
            .overlay {
                content
                    .clipShape(inner)
                    .padding(bezelWidth)
            }
            .overlay {
                outer.stroke(Color.white.opacity(0.16), lineWidth: 0.5)
            }
            .overlay(alignment: .top) {
                if kind == .laptop {
                    // The notch sits in the bezel, not over the desktop.
                    Capsule()
                        .fill(bezel)
                        .frame(width: screenWidth * 0.16, height: bezelWidth * 1.6)
                }
            }
            .frame(width: screenWidth, height: screenHeight + (kind == .iMac ? chinHeight : 0))
            .overlay(alignment: .bottom) {
                if kind == .iMac {
                    Rectangle().fill(metal).frame(height: chinHeight)
                }
            }
            .clipShape(outer)
    }

    private var bezelWidth: CGFloat { kind == .laptop ? 2.5 : 3 }
    private var chinHeight: CGFloat { max(screenHeight * 0.08, 5) }

    @ViewBuilder
    private var stand: some View {
        switch kind {
        case .laptop:
            // Tapered base with the thumb notch, slightly wider than the lid.
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 2.5,
                                       bottomTrailingRadius: 2.5, topTrailingRadius: 1)
                    .fill(LinearGradient(colors: [metal, metalDark],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: screenWidth * 1.06, height: 5)
                Capsule()
                    .fill(metalDark)
                    .frame(width: screenWidth * 0.14, height: 2)
                    .padding(.top, 0.5)
            }
        case .desktopDisplay:
            VStack(spacing: 0) {
                Trapezoid(topInset: 0.10)
                    .fill(LinearGradient(colors: [metalDark, metal],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: screenWidth * 0.17, height: screenHeight * 0.16)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LinearGradient(colors: [metal, metalDark],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: screenWidth * 0.42, height: 4)
            }
        case .iMac:
            VStack(spacing: 0) {
                Trapezoid(topInset: 0.18)
                    .fill(LinearGradient(colors: [metalDark, metal],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: screenWidth * 0.24, height: screenHeight * 0.14)
                Capsule()
                    .fill(metal)
                    .frame(width: screenWidth * 0.40, height: 3.5)
            }
        }
    }
}

/// Stand neck — narrower at the top than the bottom.
struct Trapezoid: Shape {
    /// Fraction of the width taken off each side of the top edge.
    var topInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * topInset
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
