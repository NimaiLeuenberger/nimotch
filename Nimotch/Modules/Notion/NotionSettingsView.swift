import SwiftUI

struct NotionSettingsView: View {
    @Bindable var notion: NotionService
    @State private var tokenDraft = ""
    @State private var picker: PickerTarget?

    enum PickerTarget: Identifiable {
        case add
        case change(UUID)
        var id: String {
            switch self {
            case .add: "add"
            case .change(let id): id.uuidString
            }
        }
    }

    var body: some View {
        Form {
            Section("Connection") { connection }
            Section {
                if notion.widgets.isEmpty {
                    Text("No widgets yet. Each widget shows one Notion page as a tab in the notch.")
                        .foregroundStyle(.secondary)
                }
                ForEach(notion.widgets) { widget in
                    WidgetRow(notion: notion, widget: widget) { picker = .change(widget.id) }
                }
                Button("Add Widget…") { picker = .add }
                    .disabled(!notion.connection.isConnected)
            } header: {
                Text("Page widgets")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $picker) { target in
            PagePickerView(client: notion.client) { page in
                switch target {
                case .add: notion.addWidget(for: page)
                case .change(let id): notion.setPage(page, for: id)
                }
            }
        }
    }

    @ViewBuilder private var connection: some View {
        switch notion.connection {
        case .connected(let name):
            LabeledContent("Connected as") {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(name)
                }
            }
            Button("Remove Token", role: .destructive) { notion.disconnect() }
        case .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking token…").foregroundStyle(.secondary)
            }
        case .none, .failed:
            SecureField("Internal integration secret", text: $tokenDraft, prompt: Text("ntn_…"))
            HStack {
                if case .failed(let message) = notion.connection {
                    Text(message).foregroundStyle(.red).font(.callout)
                }
                Spacer()
                Button("Connect") {
                    Task {
                        await notion.connect(token: tokenDraft)
                        if notion.connection.isConnected { tokenDraft = "" }
                    }
                }
                .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Create an internal integration and copy its secret.")
                Text("2. In Notion, open each page → ••• → Connections → add the integration.")
                Link("Open Notion integrations ↗", destination: URL(string: "https://www.notion.so/profile/integrations")!)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

private struct WidgetRow: View {
    let notion: NotionService
    let widget: NotionService.Widget
    let changePage: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(widget.icon ?? "📄")
            VStack(alignment: .leading, spacing: 2) {
                TextField("Tab name", text: Binding(
                    get: { widget.name },
                    set: { value in notion.update(widget.id) { $0.name = value } }
                ), prompt: Text(widget.pageTitle))
                .textFieldStyle(.plain)
                Text(widget.pageTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Hide checked", isOn: Binding(
                get: { widget.hideChecked },
                set: { value in notion.update(widget.id) { $0.hideChecked = value } }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            Menu {
                Button("Change Page…", action: changePage)
                Button("Duplicate") { notion.duplicate(widget.id) }
                Divider()
                Button("Move Up") { notion.move(widget.id, by: -1) }
                    .disabled(notion.widgets.first?.id == widget.id)
                Button("Move Down") { notion.move(widget.id, by: 1) }
                    .disabled(notion.widgets.last?.id == widget.id)
                Divider()
                Button("Remove", role: .destructive) { notion.remove(widget.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// Searchable list of pages shared with the integration. A pasted page URL also works.
struct PagePickerView: View {
    let client: NotionClient
    let onPick: (NotionPage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [NotionPage] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a Notion page").font(.headline)
            TextField("Search pages or paste a page link", text: $query)
                .textFieldStyle(.roundedBorder)
            Group {
                if loading && results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    Text("No pages found. Pages must be shared with the integration (••• → Connections).")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { page in
                        Button {
                            onPick(page)
                            dismiss()
                        } label: {
                            HStack {
                                Text(page.icon ?? "📄")
                                Text(page.title)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(height: 280)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 440)
        .task(id: query) { await search() }
    }

    private func search() async {
        try? await Task.sleep(for: .milliseconds(300))   // debounce
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            if let id = NotionLinks.pageID(from: query) {
                results = [try await client.page(id)]
            } else {
                results = try await client.search(query)
            }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
