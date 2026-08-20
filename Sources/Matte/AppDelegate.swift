import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let panel = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()

        if !AX.isTrusted {
            AX.requestTrust()
        }
        PaddingEngine.shared.start()
        StatusFile.startPublishing()
        LoginItem.refreshIfMoved()
        refreshIcon()

    }

    func applicationWillTerminate(_ notification: Notification) {
        OverlayController.shared.hide()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "rectangle.inset.filled",
                            accessibilityDescription: "Matte")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(from: sender)
            return
        }
        panel.onClose = { [weak self] in
            OverlayController.shared.hide()
            self?.refreshIcon()
        }
        panel.toggle(from: sender)
        if panel.isVisible { OverlayController.shared.flash() }
    }

    /// Right-click menu. Assigning `statusItem.menu` makes the *left* click open
    /// it too, so it is attached only for the duration of this click.
    private func showMenu(from button: NSStatusBarButton) {
        if panel.isVisible { panel.close() }

        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Keep windows inside the padding",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = Settings.shared.isEnabled ? .on : .off
        menu.addItem(toggle)

        let apply = NSMenuItem(title: "Apply Now", action: #selector(applyNow), keyEquivalent: "")
        apply.target = self
        apply.isEnabled = Settings.shared.isEnabled
        menu.addItem(apply)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Matte", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func applyNow() {
        PaddingEngine.shared.applyToAllWindows()
        OverlayController.shared.flash()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleEnabled() {
        Settings.shared.isEnabled.toggle()
        PaddingEngine.shared.settingsChanged()
        OverlayController.shared.flash()
        refreshIcon()
    }

    private func refreshIcon() {
        statusItem?.button?.appearsDisabled = !Settings.shared.isEnabled
    }
}
