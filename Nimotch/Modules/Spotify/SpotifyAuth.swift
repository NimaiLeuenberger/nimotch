import AppKit
import CryptoKit
import Network

enum SpotifyError: LocalizedError {
    case notConfigured
    case unauthorized
    case rateLimited(seconds: Double)
    case noActiveDevice
    case forbidden(String)
    case authFailed(String)
    case authTimeout
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Spotify isn't connected."
        case .unauthorized: "Spotify login expired. Reconnect in Settings → Spotify."
        case .rateLimited: "Spotify rate limit hit, retrying shortly."
        case .noActiveDevice: "No active Spotify device."
        case .forbidden(let message): "Spotify refused: \(message)"
        case .authFailed(let message): "Spotify login failed: \(message)"
        case .authTimeout: "Spotify login timed out."
        case .http(let status, let message): "Spotify error \(status): \(message)"
        }
    }
}

/// Authorization Code + PKCE with a loopback redirect (Spotify no longer allows custom schemes).
enum SpotifyAuth {
    static let port: UInt16 = 43117
    static let redirectURI = "http://127.0.0.1:\(port)/callback"
    static let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"

    struct Code: Sendable {
        let code: String
        let verifier: String
    }

    /// Opens the Spotify consent page in the browser and waits for the redirect.
    @MainActor
    static func requestCode(clientID: String) async throws -> Code {
        let verifier = randomString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = randomString(length: 16)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: state),
        ]

        let receiver = LoopbackReceiver()
        async let callback = receiver.waitForCallback(port: port, timeout: 180)
        try await Task.sleep(for: .milliseconds(150))   // let the listener come up
        NSWorkspace.shared.open(components.url!)
        let items = try await callback.queryItems ?? []
        NSApp.activate()

        if let error = items.first(where: { $0.name == "error" })?.value {
            throw SpotifyError.authFailed(error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else { throw SpotifyError.authFailed("invalid callback") }
        return Code(code: code, verifier: verifier)
    }

    private static func randomString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// One-shot HTTP listener on 127.0.0.1 that captures the OAuth redirect.
final class LoopbackReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.nimai.nimotch.oauth")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URLComponents, Error>?

    func waitForCallback(port: UInt16, timeout: TimeInterval) async throws -> URLComponents {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.allowLocalEndpointReuse = true
                    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
                    let listener = try NWListener(using: parameters)
                    listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                    listener.stateUpdateHandler = { [weak self] state in
                        if case .failed(let error) = state { self?.finish(.failure(error)) }
                    }
                    listener.start(queue: self.queue)
                    self.listener = listener
                    self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                        self?.finish(.failure(SpotifyError.authTimeout))
                    }
                } catch {
                    self.finish(.failure(error))
                }
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let isCallback = target.hasPrefix("/callback")
            let html = isCallback
                ? "<html><body style='font:16px -apple-system;text-align:center;padding-top:80px'>nimotch is connected to Spotify. You can close this tab.</body></html>"
                : "Not found"
            let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if isCallback, let components = URLComponents(string: "http://127.0.0.1\(target)") {
                self?.finish(.success(components))
            }
        }
    }

    private func finish(_ result: Result<URLComponents, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        listener?.cancel()
        listener = nil
        continuation.resume(with: result)
    }
}
