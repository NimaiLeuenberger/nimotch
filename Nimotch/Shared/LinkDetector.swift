import AppKit

struct MeetingLink: Equatable {
    enum Service: String {
        case teams = "Teams", webex = "Webex", zoom = "Zoom", meet = "Google Meet"
    }

    let service: Service
    let url: URL

    /// URL to open: Teams links go straight to the Teams app when it's installed.
    var openURL: URL {
        if service == .teams,
           url.scheme == "https",
           let appURL = URL(string: "msteams" + url.absoluteString.dropFirst("https".count)),
           NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            return appURL
        }
        return url
    }

    func open() { NSWorkspace.shared.open(openURL) }
}

/// Finds Teams / Webex / Zoom / Google Meet links in event fields.
enum LinkDetector {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Returns the first meeting link found, checking `texts` in order.
    static func find(in texts: [String?]) -> MeetingLink? {
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            for url in urls(in: text) {
                if let link = classify(unwrapSafeLink(url)) { return link }
            }
        }
        return nil
    }

    static func classify(_ url: URL) -> MeetingLink? {
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.path().lowercased()
        let service: MeetingLink.Service? = switch true {
        case host == "teams.microsoft.com" || host.hasSuffix(".teams.microsoft.com") || host == "teams.live.com":
            (path.contains("meetup-join") || path.hasPrefix("/meet/") || path.hasPrefix("/l/meet")) ? .teams : nil
        case host.hasSuffix("webex.com"):
            (path.contains("/j.php") || path.contains("/meet/") || path.contains("/join/") || path.contains("/wbxmjs/") || path.contains("/m/")) ? .webex : nil
        case host == "zoom.us" || host.hasSuffix(".zoom.us"):
            (path.hasPrefix("/j/") || path.hasPrefix("/my/") || path.hasPrefix("/w/")) ? .zoom : nil
        case host == "meet.google.com":
            path.count > 1 ? .meet : nil
        default:
            nil
        }
        return service.map { MeetingLink(service: $0, url: url) }
    }

    private static func urls(in text: String) -> [URL] {
        guard let detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }

    /// Outlook wraps links as https://*.safelinks.protection.outlook.com/?url=<encoded>.
    private static func unwrapSafeLink(_ url: URL) -> URL {
        guard url.host()?.lowercased().hasSuffix("safelinks.protection.outlook.com") == true,
              let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let innerURL = URL(string: inner)
        else { return url }
        return innerURL
    }
}
