import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). Registering may surface the
/// app under System Settings › General › Login Items.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Gamely: login item \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }
}
