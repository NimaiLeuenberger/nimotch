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

    var body: some View {
        Form {
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
