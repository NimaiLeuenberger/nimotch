import SwiftUI

/// Value types the notch understands. Modules feed the notch through these:
/// - `Peek`: a short pill below the notch (`NotchViewModel.showPeek`)
/// - `LiveActivity`: icons left/right of the hardware notch while collapsed
/// - `Tab`: a page in the expanded panel (`ExpandedView`)
extension NotchViewModel {
    /// Tabs of the expanded panel. Notion has one tab per widget (or a setup tab when there are none).
    enum Tab: Hashable {
        case calendar
        case notion(UUID)
        case notionSetup
        case spotify
    }

    struct Peek: Equatable, Identifiable {
        struct Action: Equatable {
            var title: String
            var icon: String
            var perform: @MainActor () -> Void
            static func == (a: Action, b: Action) -> Bool { a.title == b.title && a.icon == b.icon }
        }
        let id = UUID()
        var icon: String
        var tint: Color = .orange
        var title: String
        var subtitle: String?
        var duration: Duration = .seconds(4)
        var action: Action?
        /// Shown instead of the icon (e.g. album art).
        var artworkURL: URL?
    }

    /// Live info shown in the wings next to the hardware notch.
    enum LiveActivity: Equatable {
        case meeting(MeetingCountdown)
        case music(MusicActivity)
        case demo
    }

    struct MusicActivity: Equatable {
        var trackID: String
        var artworkURL: URL?
    }

    struct MeetingCountdown: Equatable {
        var eventID: String
        var title: String
        var start: Date
        var color: Color
    }
}
