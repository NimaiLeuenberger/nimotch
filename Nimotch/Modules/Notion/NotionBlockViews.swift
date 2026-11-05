import SwiftUI

// MARK: - Blocks

/// A list of sibling blocks; numbers consecutive numbered-list items.
struct BlockList: View {
    let blocks: [NotionBlock]
    let hideChecked: Bool
    let notch: NotchViewModel

    var body: some View {
        ForEach(numbered, id: \.block.id) { item in
            BlockRow(block: item.block, number: item.number, hideChecked: hideChecked, notch: notch)
        }
    }

    private var numbered: [(block: NotionBlock, number: Int)] {
        var counter = 0
        return blocks.compactMap { block in
            counter = block.kind == .numbered ? counter + 1 : 0
            if hideChecked, block.kind == .toDo, block.checked { return nil }
            return (block, counter)
        }
    }
}

struct BlockRow: View {
    let block: NotionBlock
    let number: Int
    let hideChecked: Bool
    let notch: NotchViewModel
    @Environment(NotionPageStore.self) private var store
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                row
                if hasActions { actions }
            }
            // Hover = slightly brighter background. Padding is constant (and cancelled out
            // outside), so hovering never moves or re-wraps the line.
            .padding(.horizontal, Self.highlightInset)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(hovering ? 0.08 : 0))
            )
            .padding(.horizontal, -Self.highlightInset)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contextMenu { menu }

            if showsChildren, !block.children.isEmpty {
                // AnyView breaks the recursive opaque type (BlockList → BlockRow → BlockList).
                AnyView(BlockList(blocks: block.children, hideChecked: hideChecked, notch: notch))
                    .padding(.leading, 20)
            }
            if store.addingAfterID == block.id {
                AddBlockField(after: block.id, kind: block.kind.newLineKind, notch: notch, autoFocus: true)
            }
        }
    }

    static let highlightInset: CGFloat = 6

    private var showsChildren: Bool { block.kind != .toggle || expanded }

    /// Rows that get the hover "+" / "×" buttons.
    private var hasActions: Bool { block.kind.isEditableText || block.kind == .divider }

    /// "+" (add a line below) and "×" (delete). Always laid out, only faded in on hover,
    /// so their width is reserved and text never wraps differently while hovering.
    private var actions: some View {
        let enabled = hovering && !block.id.hasPrefix("temp-")
        return HStack(spacing: 2) {
            RowActionButton(icon: "plus", help: "Add a line below") {
                notch.beginTextEditing()
                store.addingAfterID = block.id
            }
            RowActionButton(icon: "xmark", help: "Delete (moves to Notion trash)") {
                store.delete(block.id)
            }
        }
        .opacity(enabled ? 1 : 0)
        .allowsHitTesting(enabled)
    }

    @ViewBuilder private var row: some View {
        switch block.kind {
        case .heading1: text(size: 17, weight: .bold).padding(.top, 6)
        case .heading2: text(size: 15, weight: .bold).padding(.top, 4)
        case .heading3: text(size: 13, weight: .semibold).padding(.top, 2)
        case .paragraph:
            if block.richText.isEmpty && store.editingBlockID != block.id {
                Color.clear.frame(height: 6)
            } else {
                text(size: 13)
            }
        case .toDo:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    store.setChecked(block.id, !block.checked)
                } label: {
                    Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(block.checked ? Color.orange : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                text(size: 13, dimmed: block.checked)
            }
        case .bulleted:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                text(size: 13)
            }
        case .numbered:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                text(size: 13)
            }
            .font(.system(size: 13))
        case .toggle:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                text(size: 13)
            }
        case .quote:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.5)).frame(width: 3)
                text(size: 13)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .callout:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(block.icon ?? "💡")
                text(size: 13)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.07)))
        case .divider:
            Divider().overlay(.white.opacity(0.15)).padding(.vertical, 4)
        case .childPage:
            Button {
                NotionLinks.open(store.page?.url, blockID: block.id)
            } label: {
                Label(block.title ?? "Untitled", systemImage: "doc.text")
                    .font(.system(size: 13))
                    .underline()
            }
            .buttonStyle(.plain)
        case .unsupported(let type):
            Button {
                NotionLinks.open(store.page?.url, blockID: block.id)
            } label: {
                Text("▸ \(type.replacingOccurrences(of: "_", with: " ")) — open in Notion")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func text(size: CGFloat, weight: Font.Weight = .regular, dimmed: Bool = false) -> some View {
        EditableBlockText(block: block, font: .system(size: size, weight: weight), dimmed: dimmed, notch: notch)
    }

    @ViewBuilder private var menu: some View {
        if block.kind.isEditableText {
            Button("Edit") {
                notch.beginTextEditing()
                store.editingBlockID = block.id
            }
        }
        Button("Add Line Below") {
            notch.beginTextEditing()
            store.addingAfterID = block.id
        }
        Button("Open in Notion") { NotionLinks.open(store.page?.url, blockID: block.id) }
        if block.kind.isEditableText || block.kind == .divider {
            Divider()
            Button("Delete", role: .destructive) { store.delete(block.id) }
        }
    }
}

private struct RowActionButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 18, height: 16)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
