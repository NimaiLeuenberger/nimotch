import Foundation

struct NowPlaying: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case mac
        case remote(device: String, type: String)
    }

    var trackID: String
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var duration: TimeInterval
    var position: TimeInterval
    var positionDate: Date
    var isPlaying: Bool
    var source: Source

    func progress(at date: Date) -> TimeInterval {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(positionDate))
    }

    var sourceLabel: String {
        switch source {
        case .mac: "Spotify on this Mac"
        case .remote(let device, _): "Playing on \(device)"
        }
    }

    var sourceIcon: String {
        switch source {
        case .mac: "laptopcomputer"
        case .remote(_, let type):
            switch type.lowercased() {
            case "smartphone": "iphone"
            case "computer": "laptopcomputer"
            case "tablet": "ipad"
            case "tv": "tv"
            case "speaker", "avr", "stb", "audiodongle": "hifispeaker"
            default: "hifispeaker"
            }
        }
    }
}
