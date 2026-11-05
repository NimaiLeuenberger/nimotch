import AppKit
import SwiftUI

/// Small in-memory image cache for album art (shared by wings, peek and the tab).
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private var images: [URL: NSImage] = [:]
    private var order: [URL] = []

    func cached(_ url: URL) -> NSImage? { images[url] }

    func load(_ url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data)
        else { return nil }
        images[url] = image
        order.append(url)
        if order.count > 40 { images.removeValue(forKey: order.removeFirst()) }
        return image
    }
}

struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat = 6
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = ArtworkCache.shared.cached(url)
            if image == nil { image = await ArtworkCache.shared.load(url) }
        }
    }
}

/// Minimal, slow equalizer for the wings while music plays.
struct EqualizerBars: View {
    var color: Color = .white.opacity(0.55)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = t * (2.2 + Double(index) * 0.9) + Double(index) * 1.3
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: 3 + 6 * (0.5 + 0.5 * sin(phase)))
                }
            }
            .frame(height: 10)
        }
    }
}
