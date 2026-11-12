import SwiftUI

struct MenuBarContent: View {
    let hub: NotchHub

    var body: some View {
        Button(hub.isAnyExpanded ? "Collapse notch" : "Open notch") {
            hub.toggleFromMenu()
        }
        Divider()
        Menu("Debug") {
            Button("Show test peek") {
                hub.showPeek(.init(icon: "bell.badge.fill", title: "Standup in 30 min", subtitle: "Microsoft Teams · 09:30"))
            }
            Toggle("Show demo wings", isOn: Binding(
                get: { hub.demoWings },
                set: { hub.setDemoWings($0) }
            ))
        }
        Divider()
        Button("Settings…") {
            hub.openSettings?()
        }
        .keyboardShortcut(",")
        Button("Quit nimotch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
