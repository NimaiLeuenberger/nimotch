import SwiftUI

/// One Notion page rendered in the notch, editable inline.
struct NotionPageView: View {
    let widget: NotionService.Widget
    let store: NotionPageStore
    let notch: NotchViewModel
    @Environment(NotionService.self) private var notion

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = store.writeError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.writeError)
        .environment(store)
        .task(id: widget.pageID) { await store.refresh(force: true) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(store.page?.title ?? widget.pageTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            IconButton(icon: widget.hideChecked ? "eye.slash" : "eye",
                       help: widget.hideChecked ? "Show checked items" : "Hide checked items") {
                notion.update(widget.id) { $0.hideChecked.toggle() }
            }
            IconButton(icon: "arrow.clockwise", help: "Refresh") {
                Task { await store.refresh(force: true) }
            }
            .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
            .animation(store.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                       value: store.isRefreshing)
            IconButton(icon: "arrow.up.forward.app", help: "Open in Notion") {
                NotionLinks.open(store.page?.url)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView().controlSize(.small)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button("Retry") { Task { await store.refresh(force: true) } }
                    .controlSize(.small)
            }
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    BlockList(blocks: store.blocks, hideChecked: widget.hideChecked, notch: notch)
                    AddBlockField(after: nil, notch: notch)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Shown in the Notion tab when no widget is configured yet.
struct NotionSetupPrompt: View {
    let notch: NotchViewModel
    @Environment(NotionService.self) private var notion

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(notion.connection.isConnected
                 ? "Add a Notion page widget in Settings → Notion."
                 : "Connect Notion in Settings → Notion to show your pages here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                notch.clickedOutside()
                notch.openSettings?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}
