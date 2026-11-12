import SwiftUI

@main
struct NimotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("nimotch", systemImage: "rectangle.topthird.inset.filled") {
            MenuBarContent(hub: appDelegate.hub)
        }
    }
}
