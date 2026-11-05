import Foundation
import ServiceManagement

/// "Open at login" via SMAppService. Only the installed copy in /Applications registers
/// itself, so dev builds from `build/` never become the login item.
@MainActor
enum LaunchAtLogin {
    private static let didSetupKey = "launchAtLogin.didSetup"

    static var isInstalled: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Turns it on once, the first time the installed app launches.
    static func enableOnFirstInstalledLaunch() {
        guard isInstalled, !UserDefaults.standard.bool(forKey: didSetupKey) else { return }
        UserDefaults.standard.set(true, forKey: didSetupKey)
        try? set(true)
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
