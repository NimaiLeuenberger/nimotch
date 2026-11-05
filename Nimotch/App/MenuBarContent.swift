import SwiftUI

struct MenuBarContent: View {
    let notch: NotchViewModel

    var body: some View {
        Button(notch.mode == .expanded ? "Collapse notch" : "Open notch") {
            notch.toggleFromMenu()
        }
        Divider()
        Menu("Debug") {
            Button("Show test peek") {
                notch.showPeek(.init(icon: "bell.badge.fill", title: "Standup in 30 min", subtitle: "Microsoft Teams · 09:30"))
            }
            Toggle("Show demo wings", isOn: Binding(
                get: { notch.demoWings },
                set: { notch.setDemoWings($0) }
            ))
        }
        Divider()
        Button("Settings…") {
            notch.openSettings?()
        }
        .keyboardShortcut(",")
        Button("Quit nimotch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
