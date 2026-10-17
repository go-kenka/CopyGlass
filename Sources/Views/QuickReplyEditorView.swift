import SwiftUI

/// Add / edit form for a quick reply.
///
/// Shown by `QuickReplyEditorPresenter` in its own dialog window: the window has no close /
/// minimize / zoom buttons, so the form is not preceded by the main window's traffic lights.
struct QuickReplyEditorView: View {
    let heading: String
    let onSave: (QuickReplyItem) -> Void
    let onCancel: () -> Void

    @Environment(\.appLanguage) private var lang
    @State private var title: String
    @State private var content: String
    @State private var shortcut: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case content
        case shortcut
    }

    private let itemID: UUID
    private let category: String?

    init(
        item: QuickReplyItem?,
        lang: AppLanguage,
        onSave: @escaping (QuickReplyItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.heading = L10n.t(item == nil ? .newQuickReply : .editQuickReply, lang: lang)
        self.onSave = onSave
        self.onCancel = onCancel
        self.itemID = item?.id ?? UUID()
        self.category = item?.category
        _title = State(initialValue: item?.title ?? "")
        _content = State(initialValue: item?.content ?? "")
        _shortcut = State(initialValue: item?.shortcut ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading)
                .font(.headline)

            labeledField(L10n.t(.title, lang: lang)) {
                TextField(L10n.t(.title, lang: lang), text: $title)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .title)
                    .editorField()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.content, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .content)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12))
                    }
            }
            .frame(maxHeight: .infinity)

            labeledField(L10n.t(.shortcutOptional, lang: lang)) {
                TextField(L10n.t(.shortcutOptional, lang: lang), text: $shortcut)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .shortcut)
                    .editorField()
            }

            HStack(spacing: 10) {
                Button(L10n.t(.cancel, lang: lang)) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t(.save, lang: lang)) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560, height: 500)
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedField = .title
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedShortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = QuickReplyItem(
            id: itemID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content,
            shortcut: trimmedShortcut.isEmpty ? nil : trimmedShortcut,
            category: category
        )
        onSave(item)
    }

    private func labeledField<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            field()
        }
    }
}

private extension View {
    /// Rounded, slightly taller replacement for the default text field chrome.
    func editorField() -> some View {
        self
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            }
    }
}
