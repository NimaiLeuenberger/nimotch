import AppKit

/// Spotify desktop app via AppleScript. Updates arrive instantly through Spotify's
/// `PlaybackStateChanged` distributed notification. Never launches Spotify.
@MainActor
final class SpotifyLocalBridge {
    nonisolated static let bundleID = "com.spotify.client"

    var onChange: ((NowPlaying?) -> Void)?
    private(set) var automationDenied = false
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.onChange?(nil) }
        })
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func refreshSoon() { Task { await refresh() } }

    func refresh() async {
        guard isRunning else { onChange?(nil); return }
        switch await AppleScriptRunner.run(Self.stateScript) {
        case .success(let output):
            automationDenied = false
            onChange?(Self.parse(output))
        case .failure(let failure):
            automationDenied = failure.isNotAuthorized
            if failure.isNotAuthorized { onChange?(nil) }
        }
    }

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private func send(_ command: String) {
        guard isRunning else { return }
        Task {
            _ = await AppleScriptRunner.run("tell application id \"\(Self.bundleID)\" to \(command)")
            await refresh()
        }
    }

    private static let stateScript = """
    tell application id "com.spotify.client"
        with timeout of 3 seconds
            set st to player state as string
            if st is "stopped" then return "stopped"
            set t to current track
            return st & linefeed & (id of t) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & ((player position as integer) as string) & linefeed & (artwork url of t)
        end timeout
    end tell
    """

    /// Parses `stateScript` output: state, id, name, artist, album, duration ms, position s, artwork URL.
    nonisolated static func parse(_ output: String) -> NowPlaying? {
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 8, parts[0] != "stopped" else { return nil }
        return NowPlaying(
            trackID: parts[1],
            title: parts[2],
            artist: parts[3],
            album: parts[4],
            artworkURL: URL(string: parts[7]),
            duration: (Double(parts[5]) ?? 0) / 1000,
            position: Double(parts[6]) ?? 0,
            positionDate: .now,
            isPlaying: parts[0] == "playing",
            source: .mac
        )
    }
}
