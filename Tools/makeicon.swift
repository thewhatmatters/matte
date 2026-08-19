// Generates the app icon PNGs used to build AppIcon.icns.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./build/icon"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for size in sizes {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { continue }
    ctx.setShouldAntialias(true)

    // Rounded-square backdrop with a soft vertical gradient.
    let inset = s * 0.06
    let plate = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2),
                             xRadius: s * 0.22, yRadius: s * 0.22)
    plate.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1)
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)

    // The padded "content" rect floating inside the screen.
    let pad = s * 0.20
    let inner = NSRect(x: pad, y: pad * 1.35, width: s - pad * 2, height: s - pad * 2.1)
    let innerPath = NSBezierPath(roundedRect: inner, xRadius: s * 0.07, yRadius: s * 0.07)
    NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.94).setFill()
    innerPath.fill()

    // Dock strip peeking out of the reserved bottom margin.
    let dockHeight = s * 0.075
    let dockWidth = s * 0.46
    let dock = NSBezierPath(roundedRect: NSRect(x: (s - dockWidth) / 2, y: pad * 0.42,
                                                width: dockWidth, height: dockHeight),
                            xRadius: dockHeight / 2, yRadius: dockHeight / 2)
    NSColor(calibratedRed: 0.38, green: 0.62, blue: 1.0, alpha: 0.95).setFill()
    dock.fill()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size).png"))
}
print("icons written to \(outDir)")
