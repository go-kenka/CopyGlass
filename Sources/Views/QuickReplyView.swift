import SwiftUI

struct QuickReplyView: View {
    @StateObject private var store = QuickReplyStore.shared
    @Environment(\.appLanguage) private var lang

    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.quickReplies, lang: lang),
                    subtitle: L10n.t(.quickRepliesSubtitle, lang: lang),
                    iconSystemName: "text.bubble.fill",
                    iconColors: [Color(red: 0.15, green: 0.78, blue: 0.75), Color(red: 0.05, green: 0.55, blue: 0.70)]
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }

            ForEach(store.items) { item in
                QuickReplyRow(item: item) {
                    presentEditor(for: item)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    presentEditor(for: item)
                }
                .contextMenu {
                    Button(L10n.t(.edit, lang: lang)) {
                        presentEditor(for: item)
                    }
                    Button(L10n.t(.delete, lang: lang), role: .destructive) {
                        store.delete(item)
                    }
                }
            }
        }
        .listStyle(.inset)
        .detailSurface()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentEditor(for: nil)
                } label: {
                    Label(L10n.t(.new, lang: lang), systemImage: "plus")
                }
            }
        }
    }

    private func presentEditor(for item: QuickReplyItem?) {
        QuickReplyEditorPresenter.shared.present(item: item) { saved in
            if item == nil {
                store.add(saved)
            } else {
                store.update(saved)
            }
        }
    }
}

struct QuickReplyRow: View {
    let item: QuickReplyItem
    var onEdit: () -> Void = {}
    @Environment(\.appLanguage) private var lang

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let shortcut = item.shortcut, !shortcut.isEmpty {
                Text(shortcut.uppercased())
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule(style: .continuous))
            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.edit, lang: lang))
        }
        .padding(.vertical, 6)
        .interactiveListRow()
    }
}
