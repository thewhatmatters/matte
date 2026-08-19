import AppKit
import SwiftUI

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}

if CommandLine.arguments.contains("--uicheck") {
    // Lays the panel out offscreen in every theme and padding mode, so clipping
    // and zero-size regressions are caught without opening the UI.
    _ = NSApplication.shared
    let available = max(320, (NSScreen.main?.visibleFrame.height ?? 900) - 120)
    let restoreTheme = Settings.shared.themeID
    let restoreMode = Settings.shared.editEdgesIndividually
    var failures = 0

    print("available height: \(Int(available))pt\n")
    for theme in Theme.all {
        Settings.shared.themeID = theme.id
        for individual in [false, true] {
            Settings.shared.editEdgesIndividually = individual
            let controller = NSHostingController(rootView: PanelRoot())
            controller.sizingOptions = [.preferredContentSize]
            controller.view.layoutSubtreeIfNeeded()
            let size = controller.view.fittingSize
            let ok = size.width > 0 && size.height > 0 && size.height <= available
            if !ok { failures += 1 }
            print(String(format: "  %-10@ %-14@ %3.0f x %3.0f  %@",
                         theme.name as NSString,
                         (individual ? "per-edge" : "single slider") as NSString,
                         size.width, size.height,
                         ok ? "PASS" : "FAIL (zero size or taller than screen)"))
        }
    }

    Settings.shared.themeID = restoreTheme
    Settings.shared.editEdgesIndividually = restoreMode
    print(failures == 0
          ? "\nPASS — \(Theme.all.count * 2) layouts fit within the screen"
          : "\nFAIL — \(failures) layout(s) bad")
    exit(failures == 0 ? 0 : 1)
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
