import SwiftUI

struct SettingsView: View {
    let notch: NotchViewModel
    let calendar: CalendarService
    let notion: NotionService
    let spotify: SpotifyService

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(notch: notch)
            }
            Tab("Calendar", systemImage: "calendar") {
                Form { CalendarSettingsView(calendar: calendar) }
                    .formStyle(.grouped)
            }
            Tab("Notion", systemImage: "doc.text") {
                NotionSettingsView(notion: notion)
            }
            Tab("Spotify", systemImage: "music.note") {
                SpotifySettingsView(spotify: spotify)
            }
        }
        .frame(width: 520, height: 520)
    }
}

private struct GeneralSettingsView: View {
    let notch: NotchViewModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open nimotch at login", isOn: $launchAtLogin)
                    .disabled(!LaunchAtLogin.isInstalled)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if !LaunchAtLogin.isInstalled {
                    Text("This is a dev build. Install with ./scripts/install.sh to use this.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if LaunchAtLogin.needsApproval {
                    HStack {
                        Text("Needs approval in System Settings → Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open") { LaunchAtLogin.openSystemSettings() }
                    }
                }
                if let launchError {
                    Text(launchError).font(.callout).foregroundStyle(.red)
                }
            }
            Section("Display") {
                if let geometry = notch.geometry {
                    LabeledContent("Built-in display", value: "\(Int(geometry.screenFrame.width)) × \(Int(geometry.screenFrame.height)) pt")
                    LabeledContent("Notch", value: "\(Int(geometry.notchSize.width)) × \(Int(geometry.notchSize.height)) pt")
                } else {
                    Text("Built-in display not available (lid closed?) — nimotch is hidden.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
