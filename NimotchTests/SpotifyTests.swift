import Foundation
import Testing
@testable import nimotch

@Suite("Spotify: parsing and merging")
struct SpotifyTests {
    func track(_ id: String, playing: Bool, source: NowPlaying.Source = .mac) -> NowPlaying {
        NowPlaying(trackID: id, title: id, artist: "", album: "", artworkURL: nil, duration: 200,
                   position: 10, positionDate: Date(timeIntervalSinceReferenceDate: 0), isPlaying: playing, source: source)
    }

    @Test func parsesAppleScriptOutput() throws {
        let output = "playing\nspotify:track:1\nSong\nArtist\nAlbum\n215000\n42\nhttps://i.scdn.co/image/x"
        let np = try #require(SpotifyLocalBridge.parse(output))
        #expect(np.trackID == "spotify:track:1")
        #expect(np.title == "Song")
        #expect(np.duration == 215)
        #expect(np.position == 42)
        #expect(np.isPlaying)
        #expect(np.source == .mac)
        #expect(np.artworkURL?.host() == "i.scdn.co")
    }

    @Test func stoppedOrMalformedOutputIsNil() {
        #expect(SpotifyLocalBridge.parse("stopped") == nil)
        #expect(SpotifyLocalBridge.parse("playing\nonly-two") == nil)
        #expect(SpotifyLocalBridge.parse("paused\nspotify:track:1\nS\nA\nB\n1000\n0\n")?.isPlaying == false)
    }

    @Test func mergePrefersPlayingMacThenPlayingRemoteThenPaused() {
        let remote = NowPlaying.Source.remote(device: "iPhone", type: "Smartphone")
        #expect(SpotifyService.merge(local: track("mac", playing: true), remote: track("phone", playing: true, source: remote))?.trackID == "mac")
        #expect(SpotifyService.merge(local: track("mac", playing: false), remote: track("phone", playing: true, source: remote))?.trackID == "phone")
        #expect(SpotifyService.merge(local: track("mac", playing: false), remote: track("phone", playing: false, source: remote))?.trackID == "mac")
        #expect(SpotifyService.merge(local: nil, remote: nil) == nil)
    }

    @Test func progressExtrapolatesWhilePlayingAndClamps() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(track("a", playing: true).progress(at: start.addingTimeInterval(5)) == 15)
        #expect(track("a", playing: true).progress(at: start.addingTimeInterval(500)) == 200)
        #expect(track("a", playing: false).progress(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func parsesWebAPITrack() throws {
        let json = """
        {"device":{"name":"Nimai's iPhone","type":"Smartphone"},"is_playing":true,"progress_ms":30000,
         "item":{"uri":"spotify:track:9","name":"Song","duration_ms":180000,"artists":[{"name":"A"},{"name":"B"}],
                 "album":{"name":"Album","images":[{"url":"https://i.scdn.co/image/big","width":640}]}}}
        """
        let np = try #require(try SpotifyWebClient.parsePlayer(Data(json.utf8)))
        #expect(np.artist == "A, B")
        #expect(np.position == 30)
        #expect(np.duration == 180)
        #expect(np.source == .remote(device: "Nimai's iPhone", type: "Smartphone"))
        #expect(np.sourceIcon == "iphone")
    }

    @Test func parsesWebAPIEpisodeAndEmptyPlayer() throws {
        let episode = """
        {"device":{"name":"Speaker","type":"Speaker"},"is_playing":false,"progress_ms":0,
         "item":{"uri":"spotify:episode:1","name":"Ep","duration_ms":60000,"show":{"name":"Show","publisher":"Pub"},
                 "images":[{"url":"https://i.scdn.co/image/ep"}]}}
        """
        let np = try #require(try SpotifyWebClient.parsePlayer(Data(episode.utf8)))
        #expect(np.artist == "Pub")
        #expect(np.album == "Show")
        #expect(np.artworkURL?.lastPathComponent == "ep")
        #expect(try SpotifyWebClient.parsePlayer(Data(#"{"is_playing":false,"item":null}"#.utf8)) == nil)
    }
}
