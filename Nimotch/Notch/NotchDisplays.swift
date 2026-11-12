import AppKit
import SwiftUI

/// A connected display, identified by a key that survives reconnects and reboots.
struct DisplayInfo: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let hasNotch: Bool

    static let builtInKey = "builtin"

    /// Built-in display: "builtin"; others: vendor/model/serial from CoreGraphics.
    static func key(isBuiltIn: Bool, vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        isBuiltIn ? builtInKey : "display-\(vendor)-\(model)-\(serial)"
    }
}

/// Which displays show a notch. Persisted per display key; by default only the
/// built-in (MacBook) display is on, external displays are off until enabled in Settings.
@MainActor
@Observable
final class NotchDisplays {
    private(set) var connected: [DisplayInfo] = []
    private var overrides: [String: Bool] {
        didSet { UserDefaults.standard.set(overrides, forKey: Self.key) }
    }

    /// Called after a setting changed (the display manager re-syncs its panels).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var screensByID: [String: NSScreen] = [:]
    private static let key = "notch.displays"

    init() {
        overrides = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
        refresh()
    }

    func isEnabled(_ display: DisplayInfo) -> Bool {
        Self.isEnabled(display, overrides: overrides)
    }

    func setEnabled(_ enabled: Bool, for display: DisplayInfo) {
        overrides[display.id] = enabled
        onChange?()
    }

    /// Connected displays that should show a notch, built-in first.
    var enabled: [(info: DisplayInfo, screen: NSScreen)] {
        connected.filter(isEnabled).compactMap { info in screensByID[info.id].map { (info, $0) } }
    }

    /// Re-reads `NSScreen.screens` (call on screen-parameter changes).
    func refresh() {
        var infos: [DisplayInfo] = []
        var screens: [String: NSScreen] = [:]
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            let base = DisplayInfo.key(isBuiltIn: CGDisplayIsBuiltin(id) != 0, vendor: CGDisplayVendorNumber(id),
                                       model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
            let key = Self.unique(base, existing: Set(screens.keys))
            let info = DisplayInfo(id: key, name: screen.localizedName, isBuiltIn: base == DisplayInfo.builtInKey,
                                   hasNotch: NotchGeometry(screen: screen).hasHardwareNotch)
            infos.append(info)
            screens[key] = screen
        }
        connected = Self.sorted(infos)
        screensByID = screens
    }

    // MARK: Pure helpers (unit-tested)

    nonisolated static func isEnabled(_ display: DisplayInfo, overrides: [String: Bool]) -> Bool {
        overrides[display.id] ?? display.isBuiltIn
    }

    /// Two identical monitors without serial numbers get "#2", "#3"… so both stay configurable.
    nonisolated static func unique(_ key: String, existing: Set<String>) -> String {
        guard existing.contains(key) else { return key }
        var index = 2
        while existing.contains("\(key)#\(index)") { index += 1 }
        return "\(key)#\(index)"
    }

    nonisolated static func sorted(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        displays.sorted { ($0.isBuiltIn ? 0 : 1, $0.name) < ($1.isBuiltIn ? 0 : 1, $1.name) }
    }
}
