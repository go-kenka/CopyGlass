import SwiftUI

struct QuickReplyView: View {
    @StateObject private var store = QuickReplyStore.shared
    @State private var showingAddSheet = false
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.quickReplies, lang: lang),
                    subtitle: L10n.t(.quickReplySubtitle, lang: lang),
                    iconSystemName: "text.bubble.fill",
                    iconColors: [Color(red: 0.15, green: 0.78, blue: 0.75), Color(red: 0.05, green: 0.55, blue: 0.70)]
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            ForEach(store.items) { item in
                QuickReplyRow(item: item)
                    .contextMenu {
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
                    showingAddSheet = true
                } label: {
                    Label(L10n.t(.new, lang: lang), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddQuickReplyView(isPresented: $showingAddSheet) { newItem in
                store.add(newItem)
            }
        }
    }
}

struct QuickReplyRow: View {
    let item: QuickReplyItem
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
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
        }
        .padding(.vertical, 6)
    }
}

struct AddQuickReplyView: View {
    @Binding var isPresented: Bool
    var onAdd: (QuickReplyItem) -> Void
    @Environment(\.appLanguage) private var lang
    
    @State private var title = ""
    @State private var content = ""
    @State private var shortcut = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t(.newQuickReply, lang: lang))
                .font(.headline)
            
            Form {
                TextField(L10n.t(.title, lang: lang), text: $title)
                TextEditor(text: $content)
                    .frame(height: 120)
                TextField(L10n.t(.shortcutOptional, lang: lang), text: $shortcut)
            }
            
            HStack {
                Button(L10n.t(.cancel, lang: lang)) { isPresented = false }
                Spacer()
                Button(L10n.t(.save, lang: lang)) {
                    let newItem = QuickReplyItem(title: title, content: content, shortcut: shortcut.isEmpty ? nil : shortcut)
                    onAdd(newItem)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || content.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 520, height: 420)
        .detailSurface()
    }
}
