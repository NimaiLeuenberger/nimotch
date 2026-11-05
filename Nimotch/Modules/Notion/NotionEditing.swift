import SwiftUI

// MARK: - Editing

/// Block text that turns into a text field on click. Return / clicking away saves, Esc cancels.
struct EditableBlockText: View {
    let block: NotionBlock
    let font: Font
    let dimmed: Bool
    let notch: NotchViewModel
    @Environment(NotionPageStore.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var isEditing: Bool { store.editingBlockID == block.id }

    var body: some View {
        if isEditing {
            TextField("", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .focused($focused)
                .onAppear {
                    draft = block.plainText
                    DispatchQueue.main.async { focused = true }
                }
                .onSubmit(commit)
                .onExitCommand { store.editingBlockID = nil }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)).padding(-3))
        } else {
            Text(block.richText.isEmpty ? AttributedString(" ") : block.richText.attributed)
                .font(font)
                .strikethrough(dimmed)
                .foregroundStyle(dimmed ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard block.kind.isEditableText, !block.id.hasPrefix("temp-") else { return }
                    notch.beginTextEditing()
                    store.editingBlockID = block.id
                }
        }
    }

    private func commit() {
        guard isEditing else { return }
        store.editingBlockID = nil
        store.setText(block.id, draft.trimmingCharacters(in: .newlines))
    }
}

/// Inline field that adds a line. At the page end (`after == nil`) it stays open for adding
/// several items; below a row (the row's "+") it closes after one line.
struct AddBlockField: View {
    let after: String?
    var kind: NotionBlock.Kind = .toDo
    let notch: NotchViewModel
    var autoFocus = false
    @Environment(NotionPageStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker
            TextField(after == nil ? "Add a to-do" : "New line", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand(perform: close)
        }
        .onAppear {
            if autoFocus { DispatchQueue.main.async { focused = true } }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { notch.beginTextEditing() } else if after != nil { close() }
        }
    }

    /// Mirrors the look of the line that will be created.
    @ViewBuilder private var marker: some View {
        switch (after, kind) {
        case (.some, .toDo):
            Image(systemName: "square").font(.system(size: 13)).foregroundStyle(.tertiary)
        case (.some, .bulleted):
            Text("•").foregroundStyle(.tertiary)
        default:
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 13)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return close() }
        store.addBlock(trimmed, kind: kind, after: after)
        text = ""
        if after != nil { close() }
    }

    private func close() {
        text = ""
        if after != nil, store.addingAfterID == after { store.addingAfterID = nil }
        focused = false
    }
}
