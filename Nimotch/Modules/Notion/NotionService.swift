import SwiftUI

/// Notion connection (token) and the user's page widgets.
@MainActor
@Observable
final class NotionService {
    struct Widget: Codable, Identifiable, Equatable {
        var id = UUID()
        var pageID: String
        var pageTitle: String
        var name: String
        var icon: String?
        var hideChecked = false

        var displayName: String { name.isEmpty ? pageTitle : name }
    }

    enum Connection: Equatable {
        case none, checking
        case connected(String)
        case failed(String)

        var isConnected: Bool { if case .connected = self { true } else { false } }
    }

    private(set) var connection: Connection = .none
    private(set) var widgets: [Widget] = [] {
        didSet { saveWidgets() }
    }

    @ObservationIgnored let client = NotionClient()
    @ObservationIgnored private var stores: [UUID: NotionPageStore] = [:]
    private static let tokenAccount = "notion-token"
    private static let widgetsKey = "notion.widgets"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.widgetsKey),
           let saved = try? JSONDecoder().decode([Widget].self, from: data) {
            widgets = saved
        }
        if let token = Keychain.get(Self.tokenAccount) {
            connection = .checking
            Task { await connect(token: token, save: false) }
        }
    }

    // MARK: Token

    func connect(token raw: String, save: Bool = true) async {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        connection = .checking
        do {
            let name = try await client.validate(token: token)
            await client.setToken(token)
            if save { Keychain.set(token, for: Self.tokenAccount) }
            connection = .connected(name)
            resetStores()
        } catch NotionError.api(_, "unauthorized", _) {
            connection = .failed("Token was rejected by Notion.")
        } catch {
            // Offline etc.: keep using a saved token, it was valid before.
            if !save {
                await client.setToken(token)
                connection = .connected("Notion (offline)")
            } else {
                connection = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        Keychain.set(nil, for: Self.tokenAccount)
        Task { await client.setToken(nil) }
        connection = .none
        resetStores()
    }

    // MARK: Widgets

    /// The live store for a widget's page (created on first use, then kept polling).
    func store(for widget: Widget) -> NotionPageStore {
        if let store = stores[widget.id], store.pageID == widget.pageID { return store }
        stores[widget.id]?.stop()
        let store = NotionPageStore(pageID: widget.pageID, client: client)
        stores[widget.id] = store
        return store
    }

    func widget(_ id: UUID) -> Widget? { widgets.first { $0.id == id } }

    @discardableResult
    func addWidget(for page: NotionPage) -> Widget {
        let widget = Widget(pageID: page.id, pageTitle: page.title, name: "", icon: page.icon)
        widgets.append(widget)
        return widget
    }

    func setPage(_ page: NotionPage, for id: UUID) {
        update(id) {
            $0.pageID = page.id
            $0.pageTitle = page.title
            $0.icon = page.icon
        }
    }

    func duplicate(_ id: UUID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        var copy = widgets[index]
        copy.id = UUID()
        if !copy.name.isEmpty { copy.name += " copy" }
        widgets.insert(copy, at: index + 1)
    }

    func remove(_ id: UUID) {
        widgets.removeAll { $0.id == id }
        stores.removeValue(forKey: id)?.stop()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard widgets.indices.contains(target) else { return }
        widgets.swapAt(index, target)
    }

    func update(_ id: UUID, _ transform: (inout Widget) -> Void) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        transform(&widgets[index])
    }

    private func resetStores() {
        stores.values.forEach { $0.stop() }
        stores.removeAll()
    }

    private func saveWidgets() {
        if let data = try? JSONEncoder().encode(widgets) {
            UserDefaults.standard.set(data, forKey: Self.widgetsKey)
        }
    }
}
