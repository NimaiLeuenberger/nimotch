import SwiftUI

/// Live copy of one Notion page. Polls every 30 s (one cheap request while nothing
/// changed) and applies edits optimistically, rolling back if Notion rejects them.
@MainActor
@Observable
final class NotionPageStore {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    let pageID: String
    private(set) var page: NotionPage?
    private(set) var blocks: [NotionBlock] = []
    private(set) var phase: Phase = .idle
    private(set) var isRefreshing = false
    private(set) var writeError: String?

    /// Block whose text is being edited inline (polling won't overwrite while set).
    var editingBlockID: String?
    /// Block after which an inline "add to-do" field is shown.
    var addingAfterID: String?

    static let pollInterval: Duration = .seconds(30)

    @ObservationIgnored private let client: NotionClient
    @ObservationIgnored private var inFlightWrites = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var errorTask: Task<Void, Never>?

    init(pageID: String, client: NotionClient) {
        self.pageID = pageID
        self.client = client
        pollTask = Task { [weak self] in
            await self?.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                await self?.refresh(force: false)
            }
        }
    }

    func stop() { pollTask?.cancel() }

    // MARK: Reading

    /// Reloads blocks when the page changed (or always, when `force`).
    func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if blocks.isEmpty, page == nil { phase = .loading }
        do {
            let latest = try await client.page(pageID)
            let changed = latest.lastEdited != page?.lastEdited
            if force || changed || blocks.isEmpty {
                let tree = try await client.blockTree(pageID)
                // Don't clobber local state while the user is typing or a write is pending;
                // keep the old timestamp so the next poll tries again.
                guard inFlightWrites == 0, editingBlockID == nil else { return }
                blocks = tree
            }
            page = latest
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if blocks.isEmpty { phase = .failed(error.localizedDescription) } else { showWriteError(error) }
        }
    }

    // MARK: Writing

    func setChecked(_ id: String, _ checked: Bool) {
        update(id) { $0.checked = checked }
        write { [client] in try await client.setChecked(id, checked) }
            revert: { [weak self] in self?.update(id) { $0.checked = !checked } }
    }

    func setText(_ id: String, _ text: String) {
        guard let old = find(id), old.plainText != text else { return }
        update(id) { $0.richText = text.isEmpty ? [] : [RichText(plain: text)] }
        let apiType = old.kind.apiType
        write { [client] in try await client.setText(id, apiType: apiType, text: text) }
            revert: { [weak self] in self?.update(id) { $0.richText = old.richText } }
    }

    func delete(_ id: String) {
        let snapshot = blocks
        NotionBlockTree.remove(id, from: &blocks)
        write { [client] in try await client.delete(id) }
            revert: { [weak self] in self?.blocks = snapshot }
    }

    /// Adds a block after `afterID` (as its sibling) or at the end of the page.
    func addBlock(_ text: String, kind: NotionBlock.Kind = .toDo, after afterID: String?) {
        let parentID = afterID.flatMap { find($0)?.parentID } ?? pageID
        let temp = NotionBlock(id: "temp-\(UUID().uuidString)", parentID: parentID, kind: kind,
                               richText: [RichText(plain: text)], checked: false, hasChildren: false)
        NotionBlockTree.insert(temp, after: afterID, parentID: parentID, pageID: pageID, into: &blocks)
        inFlightWrites += 1
        Task { [client] in
            defer { inFlightWrites -= 1 }
            do {
                let created = try await client.appendBlock(parentID: parentID, kind: kind, text: text, after: afterID)
                NotionBlockTree.replace(temp.id, with: created, in: &blocks)
            } catch {
                NotionBlockTree.remove(temp.id, from: &blocks)
                showWriteError(error)
            }
        }
    }

    private func write(_ operation: @escaping @Sendable () async throws -> Void, revert: @escaping @MainActor () -> Void) {
        inFlightWrites += 1
        Task {
            defer { inFlightWrites -= 1 }
            do { try await operation() } catch {
                revert()
                showWriteError(error)
            }
        }
    }

    private func showWriteError(_ error: Error) {
        writeError = error.localizedDescription
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.writeError = nil
        }
    }

    // MARK: Tree helpers

    func find(_ id: String) -> NotionBlock? { NotionBlockTree.find(id, in: blocks) }

    private func update(_ id: String, _ transform: (inout NotionBlock) -> Void) {
        NotionBlockTree.update(id, in: &blocks, transform)
    }
}
