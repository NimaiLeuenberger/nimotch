import AppKit
import SwiftUI

/// Merges the Mac Spotify app (instant, AppleScript) with the Web API (any device, polled).
@MainActor
@Observable
final class SpotifyService {
    enum WebConnection: Equatable {
        case notConfigured, connecting
        case connected(String)
        case failed(String)

        var isConnected: Bool { if case .connected = self { true } else { false } }
    }

    private(set) var local: NowPlaying?
    private(set) var remote: NowPlaying?
    private(set) var web: WebConnection = .notConfigured
    private(set) var controlError: String?
    var macAutomationDenied: Bool { bridge.automationDenied }

    var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Keys.clientID) }
    }
    var peekOnTrackChange: Bool {
        didSet { UserDefaults.standard.set(peekOnTrackChange, forKey: Keys.peek) }
    }

    /// What to show: whatever is playing (Mac first), else the last paused state.
    var nowPlaying: NowPlaying? { Self.merge(local: local, remote: remote) }

    /// Mac app wins while it plays; then any playing remote device; then the last paused state.
    nonisolated static func merge(local: NowPlaying?, remote: NowPlaying?) -> NowPlaying? {
        if let local, local.isPlaying { return local }
        if let remote, remote.isPlaying { return remote }
        return local ?? remote
    }

    @ObservationIgnored private let bridge = SpotifyLocalBridge()
    @ObservationIgnored private let client = SpotifyWebClient()
    @ObservationIgnored private let notch: NotchViewModel
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastTrackID: String?
    @ObservationIgnored private var hasInitialState = false
    @ObservationIgnored private var errorTask: Task<Void, Never>?

    private enum Keys {
        static let clientID = "spotify.clientID"
        static let peek = "spotify.peekOnTrackChange"
    }

    init(notch: NotchViewModel) {
        self.notch = notch
        UserDefaults.standard.register(defaults: [Keys.peek: true])
        clientID = UserDefaults.standard.string(forKey: Keys.clientID) ?? ""
        peekOnTrackChange = UserDefaults.standard.bool(forKey: Keys.peek)

        bridge.onChange = { [weak self] state in
            self?.local = state
            self?.didUpdate()
        }
        bridge.refreshSoon()

        if !clientID.isEmpty, let refreshToken = Keychain.get(SpotifyWebClient.refreshTokenAccount) {
            web = .connecting
            Task {
                await client.configure(clientID: clientID, refreshToken: refreshToken)
                do {
                    web = .connected(try await client.displayName())
                } catch SpotifyError.unauthorized {
                    web = .failed("Login expired. Connect again.")
                } catch {
                    web = .connected("Spotify (offline)")
                }
            }
        }
        startPolling()
    }

    // MARK: Connection

    func connect() async {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        web = .connecting
        do {
            let code = try await SpotifyAuth.requestCode(clientID: id)
            try await client.exchange(code: code, clientID: id)
            web = .connected(try await client.displayName())
            _ = await poll()
        } catch {
            web = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        Keychain.set(nil, for: SpotifyWebClient.refreshTokenAccount)
        Task { await client.configure(clientID: nil, refreshToken: nil) }
        web = .notConfigured
        remote = nil
        didUpdate()
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    // MARK: Controls

    func playPause() {
        guard let current = nowPlaying else { return }
        if current.source == .mac { return bridge.playPause() }
        var updated = current
        updated.position = current.progress(at: .now)
        updated.positionDate = .now
        updated.isPlaying.toggle()
        remote = updated
        didUpdate()
        remoteCommand(current.isPlaying ? .pause : .play)
    }

    func next() {
        guard let current = nowPlaying else { return }
        current.source == .mac ? bridge.next() : remoteCommand(.next)
    }

    func previous() {
        guard let current = nowPlaying else { return }
        current.source == .mac ? bridge.previous() : remoteCommand(.previous)
    }

    func openSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyLocalBridge.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func remoteCommand(_ command: SpotifyWebClient.Command) {
        Task {
            do {
                try await client.send(command)
                try? await Task.sleep(for: .milliseconds(600))
                _ = await poll()
            } catch {
                showControlError(error)
                _ = await poll()
            }
        }
    }

    private func showControlError(_ error: Error) {
        controlError = error.localizedDescription
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.controlError = nil
        }
    }

    // MARK: Polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.poll()
                try? await Task.sleep(for: delay)
            }
        }
    }

    /// Fetches remote playback; returns how long to wait before the next poll.
    private func poll() async -> Duration {
        guard web.isConnected else { return .seconds(5) }
        do {
            remote = try await client.playbackState()
            didUpdate()
            if local?.isPlaying == true { return .seconds(30) }
            return remote?.isPlaying == true ? .seconds(3) : .seconds(15)
        } catch SpotifyError.rateLimited(let seconds) {
            return .seconds(max(seconds, 5))
        } catch SpotifyError.unauthorized {
            web = .failed("Login expired. Connect again.")
            return .seconds(30)
        } catch {
            return .seconds(30)
        }
    }

    // MARK: Notch

    private func didUpdate() {
        let current = nowPlaying
        notch.setMusic(current.flatMap { $0.isPlaying ? .init(trackID: $0.trackID, artworkURL: $0.artworkURL) : nil })

        if let current, current.isPlaying, current.trackID != lastTrackID {
            if hasInitialState, peekOnTrackChange, notch.mode != .expanded {
                notch.showPeek(.init(
                    icon: "music.note",
                    tint: .green,
                    title: current.title,
                    subtitle: current.artist + (current.source == .mac ? "" : " · \(current.sourceLabel)"),
                    duration: .seconds(3),
                    artworkURL: current.artworkURL
                ))
            }
            lastTrackID = current.trackID
        }
        hasInitialState = true
    }
}
