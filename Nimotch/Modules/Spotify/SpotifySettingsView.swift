import SwiftUI

struct SpotifySettingsView: View {
    @Bindable var spotify: SpotifyService

    var body: some View {
        Form {
            Section("Spotify on this Mac") {
                if spotify.macAutomationDenied {
                    HStack {
                        Text("nimotch isn't allowed to control Spotify.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Automation Settings") { spotify.openAutomationSettings() }
                    }
                } else {
                    Text("Uses the Spotify app directly: instant updates, no login.")
                        .foregroundStyle(.secondary)
                }
                Toggle("Show a peek when the track changes", isOn: $spotify.peekOnTrackChange)
            }
            Section("iPhone & other devices (Web API)") {
                switch spotify.web {
                case .connected(let name):
                    LabeledContent("Connected as") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(name)
                        }
                    }
                    Button("Disconnect", role: .destructive) { spotify.disconnect() }
                case .connecting:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Spotify login in your browser…").foregroundStyle(.secondary)
                    }
                case .notConfigured, .failed:
                    TextField("Client ID", text: $spotify.clientID, prompt: Text("from the Spotify developer dashboard"))
                    HStack {
                        if case .failed(let message) = spotify.web {
                            Text(message).foregroundStyle(.red).font(.callout)
                        }
                        Spacer()
                        Button("Connect") { Task { await spotify.connect() } }
                            .disabled(spotify.clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Create an app in the Spotify developer dashboard (API: Web API).")
                        Text("2. Add this Redirect URI exactly:")
                        Text(SpotifyAuth.redirectURI)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                        Text("3. Paste the app's Client ID above and click Connect.")
                        Link("Open Spotify developer dashboard ↗", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
