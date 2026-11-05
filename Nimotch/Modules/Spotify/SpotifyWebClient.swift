import Foundation

/// Spotify Web API client: token refresh + player endpoints.
actor SpotifyWebClient {
    enum Command: Sendable { case play, pause, next, previous }

    static let refreshTokenAccount = "spotify-refresh-token"

    private var clientID: String?
    private var refreshToken: String?
    private var accessToken: String?
    private var expiry = Date.distantPast

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private struct PlayerResponse: Decodable {
        struct Device: Decodable { let name: String; let type: String }
        struct Image: Decodable { let url: URL; let width: Int? }
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String; let images: [Image]? }
        struct Show: Decodable { let name: String; let publisher: String? }
        struct Item: Decodable {
            let uri: String
            let name: String
            let duration_ms: Double
            let artists: [Artist]?
            let album: Album?
            let show: Show?
            let images: [Image]?
        }
        let device: Device?
        let is_playing: Bool
        let progress_ms: Double?
        let item: Item?
    }

    private struct Profile: Decodable { let display_name: String?; let id: String? }
    private struct APIError: Decodable {
        struct Inner: Decodable { let status: Int?; let message: String?; let reason: String? }
        let error: Inner?
    }

    func configure(clientID: String?, refreshToken: String?) {
        self.clientID = clientID
        self.refreshToken = refreshToken
        accessToken = nil
        expiry = .distantPast
    }

    var isConfigured: Bool { clientID != nil && refreshToken != nil }

    // MARK: Auth

    func exchange(code: SpotifyAuth.Code, clientID: String) async throws {
        try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code.code,
            "redirect_uri": SpotifyAuth.redirectURI,
            "client_id": clientID,
            "code_verifier": code.verifier,
        ])
        self.clientID = clientID
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, expiry > Date().addingTimeInterval(60) { return accessToken }
        guard let clientID, let refreshToken else { throw SpotifyError.notConfigured }
        try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        guard let accessToken else { throw SpotifyError.unauthorized }
        return accessToken
    }

    private func tokenRequest(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 400 || status == 401 { throw SpotifyError.unauthorized }
            throw SpotifyError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        expiry = Date().addingTimeInterval(token.expires_in)
        if let newRefresh = token.refresh_token {
            refreshToken = newRefresh
            Keychain.set(newRefresh, for: Self.refreshTokenAccount)
        }
    }

    // MARK: API

    func displayName() async throws -> String {
        let (data, _) = try await send("GET", "me")
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        return profile.display_name ?? profile.id ?? "Spotify user"
    }

    /// Current playback on any device (nil when nothing is playing / no active device).
    func playbackState() async throws -> NowPlaying? {
        let (data, status) = try await send("GET", "me/player", query: [.init(name: "additional_types", value: "episode")])
        guard status == 200, !data.isEmpty else { return nil }
        return try Self.parsePlayer(data)
    }

    /// Parses a `GET /me/player` body (tracks and podcast episodes).
    static func parsePlayer(_ data: Data, now: Date = .now) throws -> NowPlaying? {
        let player = try JSONDecoder().decode(PlayerResponse.self, from: data)
        guard let item = player.item else { return nil }
        let images = item.album?.images ?? item.images ?? []
        return NowPlaying(
            trackID: item.uri,
            title: item.name,
            artist: item.artists?.map(\.name).joined(separator: ", ") ?? item.show?.publisher ?? item.show?.name ?? "",
            album: item.album?.name ?? item.show?.name ?? "",
            artworkURL: images.first?.url,
            duration: item.duration_ms / 1000,
            position: (player.progress_ms ?? 0) / 1000,
            positionDate: now,
            isPlaying: player.is_playing,
            source: .remote(device: player.device?.name ?? "another device", type: player.device?.type ?? "")
        )
    }

    func send(_ command: Command) async throws {
        switch command {
        case .play: _ = try await send("PUT", "me/player/play")
        case .pause: _ = try await send("PUT", "me/player/pause")
        case .next: _ = try await send("POST", "me/player/next")
        case .previous: _ = try await send("POST", "me/player/previous")
        }
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [], retried: Bool = false) async throws -> (Data, Int) {
        let token = try await validAccessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/\(path)")!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" { request.setValue("0", forHTTPHeaderField: "Content-Length") }

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        switch status {
        case 200..<300:
            return (data, status)
        case 401 where !retried:
            accessToken = nil
            return try await send(method, path, query: query, retried: true)
        case 401:
            throw SpotifyError.unauthorized
        case 429:
            throw SpotifyError.rateLimited(seconds: Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10)
        default:
            let error = (try? JSONDecoder().decode(APIError.self, from: data))?.error
            if error?.reason == "NO_ACTIVE_DEVICE" || status == 404 { throw SpotifyError.noActiveDevice }
            if status == 403 { throw SpotifyError.forbidden(error?.message ?? "not allowed") }
            throw SpotifyError.http(status, error?.message ?? "")
        }
    }
}
