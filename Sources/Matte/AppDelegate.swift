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
            toggleEnabled()
            return
        }
        panel.onClose = { [weak self] in
            OverlayController.shared.hide()
            self?.refreshIcon()
        }
        panel.toggle(from: sender)
        if panel.isVisible { OverlayController.shared.flash() }
    }

    private func toggleEnabled() {
        Settings.shared.isEnabled.toggle()
        PaddingEngine.shared.settingsChanged()
        OverlayController.shared.flash()
        refreshIcon()
    }

    private func refreshIcon() {
        statusItem?.button?.appearsDisabled = !Settings.shared.isEnabled
    }
}
