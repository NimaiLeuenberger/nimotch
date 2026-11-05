import SwiftUI

struct NowPlayingView: View {
    @Environment(SpotifyService.self) private var spotify

    var body: some View {
        if let track = spotify.nowPlaying {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    ArtworkView(url: track.artworkURL, size: 124, cornerRadius: 10)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                        .onTapGesture { spotify.openSpotify() }
                        .help("Open Spotify")
                    info(track)
                }
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity)
                if let error = spotify.controlError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }
            }
        } else {
            emptyState
        }
    }

    private func info(_ track: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(track.sourceLabel, systemImage: track.sourceIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(track.source == .mac ? Color.secondary : .green)
            Text(track.title)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(2)
            Text(track.artist)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(track.album)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            ProgressRow(track: track)
                .padding(.top, 6)
            controls(track)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func controls(_ track: NowPlaying) -> some View {
        HStack(spacing: 26) {
            ControlButton(icon: "backward.fill", size: 15) { spotify.previous() }
            ControlButton(icon: track.isPlaying ? "pause.fill" : "play.fill", size: 22) { spotify.playPause() }
            ControlButton(icon: "forward.fill", size: 15) { spotify.next() }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Nothing playing on Spotify")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if !spotify.web.isConnected {
                Text("Connect Spotify in Settings to also see your iPhone.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProgressRow: View {
    let track: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = track.progress(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(.white.opacity(0.85))
                            .frame(width: proxy.size.width * (track.duration > 0 ? progress / track.duration : 0))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Self.format(progress))
                    Spacer()
                    Text("-" + Self.format(max(0, track.duration - progress)))
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ControlButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
                .scaleEffect(hovering ? 1.1 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}
