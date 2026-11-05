import AppKit
import SwiftUI

/// Composition root: creates every service once and wires modules into the notch.
///
/// Adding a module = create its service here, inject it in `environment(_:)`,
/// and (optionally) add a tab in `ExpandedView` and a settings tab in `SettingsView`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let notch = NotchViewModel()
    // Lazy so unit tests (which host the app) don't touch EventKit, Keychain or the network.
    private(set) lazy var calendar = CalendarService()
    private(set) lazy var notion = NotionService()
    private(set) lazy var spotify = SpotifyService(notch: notch)

    private var windowController: NotchWindowController?
    private var meetingAlerts: MeetingAlertScheduler?
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        environment(SettingsView(notch: notch, calendar: calendar, notion: notion, spotify: spotify))
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        notch.openSettings = { [weak self] in self?.settingsWindow.show() }
        notch.onStopCountdown = { [weak self] id in self?.calendar.hideCountdown(for: id) }

        windowController = NotchWindowController(
            viewModel: notch,
            rootView: environment(NotchRootView(viewModel: notch))
        )
        meetingAlerts = MeetingAlertScheduler(calendar: calendar, notch: notch)
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
        case "expanded": notch.tapNotch()
        case "settings": settingsWindow.show()
        case "wings": notch.setDemoWings(true)
        case "peek":
            notch.showPeek(.init(icon: "bell.badge.fill", title: "Standup in 30 min",
                                 subtitle: "Microsoft Teams · 09:30", duration: .seconds(30)))
        default: break
        }
    }
}
