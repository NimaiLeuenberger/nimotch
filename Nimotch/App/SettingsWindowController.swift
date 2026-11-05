import AppKit
import SwiftUI

/// Hosts SettingsView in a regular window. Works from anywhere (menu bar, notch button),
/// unlike SwiftUI's openSettings, which isn't reliable from an NSHostingView in a panel.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeContent: () -> AnyView

    init(makeContent: @escaping () -> some View) {
        self.makeContent = { AnyView(makeContent()) }
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
        window.title = "nimotch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("nimotch.settings")
        if !window.setFrameUsingName("nimotch.settings") {
            window.center()
        }
        return window
    }
}
