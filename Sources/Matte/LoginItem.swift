import Foundation
import ServiceManagement

enum LoginItem {
    private static let recordedPathKey = "loginItemBundlePath"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                UserDefaults.standard.set(Bundle.main.bundlePath, forKey: recordedPathKey)
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                UserDefaults.standard.removeObject(forKey: recordedPathKey)
            }
        } catch {
            NSLog("Matte: login item change failed — \(error.localizedDescription)")
        }
    }

    /// The registration is keyed on both the bundle path and the bundle
    /// identifier, so moving the app *or* renaming its identifier silently
    /// detaches it. A recorded path means the user asked for this, so re-attach.
    static func refreshIfMoved() {
        let current = Bundle.main.bundlePath
        guard let recorded = UserDefaults.standard.string(forKey: recordedPathKey) else { return }
        guard !(isEnabled && recorded == current) else { return }
        // Detached registrations throw on unregister, and after a bundle
        // identifier change there is nothing registered to us at all — so this
        // must not abort the re-register that follows it.
        try? SMAppService.mainApp.unregister()
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(current, forKey: recordedPathKey)
            NSLog("Matte: login item re-registered for \(current)")
        } catch {
            NSLog("Matte: login item refresh failed — \(error.localizedDescription)")
        }
    }
}
