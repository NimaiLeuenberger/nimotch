import AppKit
import SwiftUI

/// Composition root: creates every service once and wires modules into the notch.
///
/// Adding a module = create its service here, inject it in `environment(_:)`,
/// and (optionally) add a tab in `ExpandedView` and a settings tab in `SettingsView`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Modules send peeks and live activities here; it fans out to every display's notch.
    let hub = NotchHub()
    // Lazy so unit tests (which host the app) don't touch screens, EventKit, Keychain or the network.
    private(set) lazy var displays = NotchDisplays()
    private(set) lazy var calendar = CalendarService()
    private(set) lazy var notion = NotionService()
    private(set) lazy var spotify = SpotifyService(notch: hub)

    private var displayManager: NotchDisplayManager?
    private var meetingAlerts: MeetingAlertScheduler?
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        environment(SettingsView(displays: displays, calendar: calendar, notion: notion, spotify: spotify))
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        LaunchAtLogin.enableOnFirstInstalledLaunch()

        hub.openSettings = { [weak self] in self?.settingsWindow.show() }
        hub.onStopCountdown = { [weak self] id in self?.calendar.hideCountdown(for: id) }

        displayManager = NotchDisplayManager(hub: hub, displays: displays) { [unowned self] notch in
            environment(NotchRootView(viewModel: notch))
        }
        meetingAlerts = MeetingAlertScheduler(calendar: calendar, notch: hub)
        Task { await calendar.requestAccessIfNeeded() }
        applyDemoArgument()
    }

    /// Injects every module service, so any view can use `@Environment(XService.self)`.
    private func environment(_ view: some View) -> some View {
        view
            .environment(calendar)
            .environment(notion)
            .environment(spotify)
    }

    /// Dev helper: `open nimotch.app --args -NimotchDemo expanded|peek|wings|settings`
    private func applyDemoArgument() {
        switch UserDefaults.standard.string(forKey: "NimotchDemo") {
        case "expanded": hub.notches.first?.tapNotch()
        case "settings": settingsWindow.show()
        case "wings": hub.setDemoWings(true)
        case "peek":
            hub.showPeek(.init(icon: "bell.badge.fill", title: "Standup in 30 min",
                                 subtitle: "Microsoft Teams · 09:30", duration: .seconds(30)))
        default: break
        }
    }
}
