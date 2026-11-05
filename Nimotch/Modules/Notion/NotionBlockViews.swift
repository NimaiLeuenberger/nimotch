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
            row
                .onHover { hovering = $0 }
                .contextMenu { menu }
            if showsChildren, !block.children.isEmpty {
                // AnyView breaks the recursive opaque type (BlockList → BlockRow → BlockList).
                AnyView(BlockList(blocks: block.children, hideChecked: hideChecked, notch: notch))
                    .padding(.leading, 20)
            }
            if store.addingAfterID == block.id {
                AddTodoField(after: block.id, notch: notch, autoFocus: true)
            }
        }
    }

    private var showsChildren: Bool { block.kind != .toggle || expanded }

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
                deleteButton
            }
        case .bulleted:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                text(size: 13)
                deleteButton
            }
        case .numbered:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                text(size: 13)
                deleteButton
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

    @ViewBuilder private var deleteButton: some View {
        if hovering, !block.id.hasPrefix("temp-") {
            Button { store.delete(block.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete (moves to Notion trash)")
        }
    }

    @ViewBuilder private var menu: some View {
        if block.kind.isEditableText {
            Button("Edit") {
                notch.beginTextEditing()
                store.editingBlockID = block.id
            }
        }
        Button("Add to-do below") {
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
