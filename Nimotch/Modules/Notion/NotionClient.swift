import Foundation

enum NotionError: LocalizedError {
    case noToken
    case api(status: Int, code: String, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noToken: "No Notion token. Add one in Settings → Notion."
        case .api(_, "object_not_found", _): "Page not found. Is it shared with your nimotch integration?"
        case .api(_, "unauthorized", _): "Notion token is invalid."
        case .api(_, "restricted_resource", _): "The integration has no access to this page."
        case .api(let status, _, let message): "Notion error \(status): \(message)"
        case .badResponse: "Unexpected response from Notion."
        }
    }
}

/// Notion REST client. Serialises requests at ~3/s and honours 429 Retry-After.
actor NotionClient {
    static let apiVersion = "2022-06-28"
    private let baseURL = URL(string: "https://api.notion.com/v1/")!
    private let minInterval: TimeInterval = 0.35
    private var token: String?
    private var nextSlot = Date.distantPast

    private struct List<T: Decodable & Sendable>: Decodable, Sendable {
        let results: [T]
        let has_more: Bool?
        let next_cursor: String?
    }
    private struct Empty: Decodable, Sendable {}
    private struct Me: Decodable, Sendable { let name: String? }
    private struct APIError: Decodable { let code: String?; let message: String? }

    func setToken(_ token: String?) { self.token = token }

    /// Validates a token; returns the integration's name.
    func validate(token candidate: String) async throws -> String {
        let me: Me = try await send("GET", "users/me", token: candidate)
        return me.name ?? "Notion integration"
    }

    func search(_ query: String) async throws -> [NotionPage] {
        let body: [String: Any] = [
            "query": query,
            "filter": ["property": "object", "value": "page"],
            "sort": ["direction": "descending", "timestamp": "last_edited_time"],
            "page_size": 25,
        ]
        let list: List<NotionPage> = try await send("POST", "search", body: body)
        return list.results
    }

    func page(_ id: String) async throws -> NotionPage {
        try await send("GET", "pages/\(id)")
    }

    /// Children of `blockID`, recursively (for block types nimotch renders) up to `maxDepth`.
    func blockTree(_ blockID: String, depth: Int = 0, maxDepth: Int = 3) async throws -> [NotionBlock] {
        var blocks: [NotionBlock] = []
        var cursor: String?
        repeat {
            var query = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "start_cursor", value: cursor)) }
            let list: List<RawBlock> = try await send("GET", "blocks/\(blockID)/children", query: query)
            blocks += list.results.map { $0.block(parentID: blockID) }
            cursor = list.has_more == true ? list.next_cursor : nil
        } while cursor != nil

        if depth < maxDepth {
            for index in blocks.indices where blocks[index].hasChildren && blocks[index].kind.rendersChildren {
                blocks[index].children = try await blockTree(blocks[index].id, depth: depth + 1, maxDepth: maxDepth)
            }
        }
        return blocks
    }

    func setChecked(_ blockID: String, _ checked: Bool) async throws {
        let _: Empty = try await send("PATCH", "blocks/\(blockID)", body: ["to_do": ["checked": checked]])
    }

    func setText(_ blockID: String, apiType: String, text: String) async throws {
        let body: [String: Any] = [apiType: ["rich_text": Self.richText(text)]]
        let _: Empty = try await send("PATCH", "blocks/\(blockID)", body: body)
    }

    /// Appends a text block (to-do, list item, paragraph…) under `parentID`, after `afterID`
    /// if given, and returns it.
    func appendBlock(parentID: String, kind: NotionBlock.Kind, text: String, after afterID: String?) async throws -> NotionBlock {
        var content: [String: Any] = ["rich_text": Self.richText(text)]
        if kind == .toDo { content["checked"] = false }
        var body: [String: Any] = [
            "children": [[
                "object": "block",
                "type": kind.apiType,
                kind.apiType: content,
            ]],
        ]
        if let afterID { body["after"] = afterID }
        let list: List<RawBlock> = try await send("PATCH", "blocks/\(parentID)/children", body: body)
        guard let created = list.results.first else { throw NotionError.badResponse }
        return created.block(parentID: parentID)
    }

    func delete(_ blockID: String) async throws {
        let _: Empty = try await send("DELETE", "blocks/\(blockID)")
    }

    // MARK: Transport

    private static func richText(_ text: String) -> [[String: Any]] {
        text.isEmpty ? [] : [["type": "text", "text": ["content": text]]]
    }

    private func waitForSlot() async {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(minInterval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
    }

    private func send<T: Decodable & Sendable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [],
        body: [String: Any]? = nil, token override: String? = nil
    ) async throws -> T {
        guard let token = override ?? token else { throw NotionError.noToken }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        for attempt in 0..<4 {
            await waitForSlot()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NotionError.badResponse }

            switch http.statusCode {
            case 200..<300:
                return try JSONDecoder().decode(T.self, from: data)
            case 429 where attempt < 3:
                let wait = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1
                nextSlot = Date().addingTimeInterval(wait)
            case 500..<600 where attempt < 2:
                try await Task.sleep(for: .seconds(1))
            default:
                let error = try? JSONDecoder().decode(APIError.self, from: data)
                throw NotionError.api(status: http.statusCode, code: error?.code ?? "", message: error?.message ?? "HTTP \(http.statusCode)")
            }
        }
        throw NotionError.badResponse
    }
}
