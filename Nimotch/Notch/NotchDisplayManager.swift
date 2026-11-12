import AppKit
import SwiftUI

/// Keeps one notch window per enabled display in sync with connected screens and settings.
@MainActor
final class NotchDisplayManager {
    private let hub: NotchHub
    private let displays: NotchDisplays
    private let makeRootView: (NotchViewModel) -> AnyView
    private var controllers: [String: NotchWindowController] = [:]
    private var screenObserver: NSObjectProtocol?

    init(hub: NotchHub, displays: NotchDisplays, makeRootView: @escaping (NotchViewModel) -> some View) {
        self.hub = hub
        self.displays = displays
        self.makeRootView = { AnyView(makeRootView($0)) }
        displays.onChange = { [weak self] in self?.sync() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        sync()
    }

    /// Creates, moves or removes notch windows so exactly the enabled displays have one.
    func sync() {
        displays.refresh()
        let wanted = displays.enabled

        for id in controllers.keys where !wanted.contains(where: { $0.info.id == id }) {
            controllers.removeValue(forKey: id)?.close()
        }
        for (info, screen) in wanted {
            if let controller = controllers[info.id] {
                controller.place(on: screen)
            } else {
                let notch = hub.makeNotch()
                controllers[info.id] = NotchWindowController(screen: screen, viewModel: notch, rootView: makeRootView(notch))
            }
        }
        hub.setNotches(wanted.compactMap { controllers[$0.info.id]?.viewModel })
    }
}
