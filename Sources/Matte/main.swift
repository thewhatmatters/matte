import AppKit
import SwiftUI

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}

if CommandLine.arguments.contains("--uicheck") {
    // Lays the panel out offscreen in every combination of its two expandable
    // sections, so clipping and zero-size regressions are caught without opening
    // the UI.
    _ = NSApplication.shared
    let available = max(320, (NSScreen.main?.visibleFrame.height ?? 900) - 120)
    let restoreEdges = Settings.shared.editEdgesIndividually
    let restoreSettings = Settings.shared.showSettingsSection
    var failures = 0

    print("displays: \(NSScreen.screens.count)   available height: \(Int(available))pt\n")
    for perEdge in [false, true] {
        for showSettings in [false, true] {
            Settings.shared.editEdgesIndividually = perEdge
            Settings.shared.showSettingsSection = showSettings
            let controller = NSHostingController(rootView: PanelRoot())
            controller.sizingOptions = [.preferredContentSize]
            controller.view.layoutSubtreeIfNeeded()
            let size = controller.view.fittingSize
            let ok = size.width > 0 && size.height > 0 && size.height <= available
            if !ok { failures += 1 }
            print(String(format: "  %-14@ %-16@ %3.0f x %3.0f  %@",
                         (perEdge ? "per-edge" : "single slider") as NSString,
                         (showSettings ? "settings open" : "settings closed") as NSString,
                         size.width, size.height, ok ? "PASS" : "FAIL"))
        }
    }

    Settings.shared.editEdgesIndividually = restoreEdges
    Settings.shared.showSettingsSection = restoreSettings
    print(failures == 0 ? "\nPASS — 4 layouts fit within the screen" : "\nFAIL — \(failures) bad")
    exit(failures == 0 ? 0 : 1)
}

if let index = CommandLine.arguments.firstIndex(of: "--render"),
   let directory = CommandLine.arguments.dropFirst(index + 1).first {
    // Renders the panel offscreen to PNGs. Design work has to be looked at, and
    // the panel can't be screenshotted from a terminal.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
    for (perEdge, showSettings) in [(false, false), (true, true)] {
        Settings.shared.editEdgesIndividually = perEdge
        Settings.shared.showSettingsSection = showSettings

        let renderer = ImageRenderer(content: PanelRoot().frame(width: 554))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            print("render failed for perEdge=\(perEdge)")
            continue
        }
        let name = perEdge ? "panel-expanded.png" : "panel-default.png"
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try? data.write(to: url)
        print("wrote \(url.lastPathComponent)  \(Int(image.size.width))x\(Int(image.size.height))")
    }
    }
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--set-padding"),
   let value = CommandLine.arguments.dropFirst(index + 1).first.flatMap(Double.init) {
    // Scriptable uniform padding, on every connected display.
    _ = NSApplication.shared
    let clamped = min(max(value, 0), Settings.maxPadding)
    var padding = EdgePadding.zero
    EdgePadding.Edge.allCases.forEach { padding[$0] = clamped }
    for screen in NSScreen.screens {
        Settings.shared.setPadding(padding, for: screen)
    }
    Settings.shared.globalPadding = padding
    print("Padding set to \(Int(clamped))pt on all edges of \(NSScreen.screens.count) display(s).")
    exit(0)
}

if CommandLine.arguments.contains("--status") {
    // Read the running app's published state rather than this process's own
    // Accessibility status — a terminal-launched copy is attributed to the
    // terminal, not to the app bundle that holds the grant.
    guard let snapshot = StatusFile.read() else {
        print("No state file at \(StatusFile.url.path) — is Matte running?")
        exit(1)
    }
    let age = Int(Date().timeIntervalSince(snapshot.writtenAt))
    print("Reported by pid \(snapshot.pid), \(age)s ago\(age > 15 ? "  ⚠️ stale — the app may not be running" : "")")
    print("Accessibility trusted: \(snapshot.trusted)")
    print(DockInfo.summary)
    print("Enabled: \(snapshot.enabled)  window scope: \(snapshot.windowScope)")
    print("Launch at login: \(snapshot.launchAtLogin)")
    for display in snapshot.displays {
        print("\(display.name)\(display.isCustom ? "  (custom padding)" : "")")
        print("  visibleFrame: \(display.visibleFrame)")
        print("  padded:       \(display.paddedRect)")
        print("  padding:      top \(Int(display.padding.top))  bottom \(Int(display.padding.bottom))  left \(Int(display.padding.left))  right \(Int(display.padding.right))")
    }
    if snapshot.trusted {
        print("\nWindows outside the padded area: \(snapshot.windowsOutsidePadding.count)")
        snapshot.windowsOutsidePadding.forEach { print("  - \($0)") }
    } else {
        print("\nNot trusted yet — grant Accessibility in System Settings → Privacy & Security.")
    }
    exit(0)
}

// One menu bar icon is enough.
let bundleID = Bundle.main.bundleIdentifier ?? "so.whatmatters.displaypadding"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    NSLog("Matte: another instance is already running.")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
