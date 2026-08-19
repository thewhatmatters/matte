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

    /// The registration records the bundle's path, so renaming or moving the app
    /// leaves it pointing at somewhere that no longer exists. Re-register once
    /// when the path has changed under us.
    static func refreshIfMoved() {
        guard isEnabled else { return }
        let current = Bundle.main.bundlePath
        guard UserDefaults.standard.string(forKey: recordedPathKey) != current else { return }
        do {
            try SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(current, forKey: recordedPathKey)
            NSLog("Matte: login item re-registered for \(current)")
        } catch {
            NSLog("Matte: login item refresh failed — \(error.localizedDescription)")
        }
    }
}
