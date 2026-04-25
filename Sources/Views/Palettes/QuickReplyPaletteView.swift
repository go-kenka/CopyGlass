import SwiftUI
import AppKit

struct QuickReplyPaletteView: View {
    @ObservedObject var store: QuickReplyStore
    @ObservedObject var model: QuickReplyPaletteModel
    let onPick: (QuickReplyItem) -> Void
    let onCancel: () -> Void
    @Environment(\.appLanguage) private var lang
    @State private var queryTaskID = UUID()
    @FocusState private var listFocused: Bool
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)
                    Text(L10n.t(.quickReply, lang: lang))
                        .font(.headline)
                    Spacer()
                    SearchField(text: $model.query, placeholder: L10n.t(.search, lang: lang), focusRequest: model.searchFocusRequest)
                        .frame(width: 220)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                
                Divider()
                
                ScrollViewReader { proxy in
                    List(selection: $model.selectedID) {
                        ForEach(model.items) { item in
                            QuickReplyPaletteRow(item: item, query: model.query)
                                .id(item.id)
                                .tag(item.id)
                                .onTapGesture(count: 2) {
                                    onPick(item)
                                }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .focusable()
                    .focused($listFocused)
                    .onChange(of: model.selectedID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.08)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    .onChange(of: model.listFocusRequest) { _, _ in
                        listFocused = true
                    }
                }
            }
        }
        .onAppear {
            updateItemsForQuery()
            model.ensureSelection()
        }
        .onChange(of: store.items) { _, _ in
            if model.query.normalizedSearchText().isEmpty {
                updateItemsForQuery()
                model.ensureSelection()
            }
        }
        .onChange(of: model.query) { _, _ in
            updateItemsForQuery()
            model.ensureSelection()
        }
        .frame(width: 520, height: 420)
    }

    private func updateItemsForQuery() {
        let q = model.query.normalizedSearchText()
        if q.isEmpty {
            model.items = store.items
            model.filteredIDs = model.items.map(\.id)
            if let selected = model.selectedID, !model.filteredIDs.contains(selected) {
                model.selectedID = model.filteredIDs.first
            }
            return
        }
        
        let taskID = UUID()
        queryTaskID = taskID
        DispatchQueue.global(qos: .userInitiated).async {
            let results = QuickReplyItemStore.shared.search(query: q, limit: 500)
            DispatchQueue.main.async {
                guard queryTaskID == taskID else { return }
                model.items = results
                model.filteredIDs = results.map(\.id)
                if let selected = model.selectedID, !model.filteredIDs.contains(selected) {
                    model.selectedID = model.filteredIDs.first
                }
            }
        }
    }
}

struct QuickReplyPaletteRow: View {
    let item: QuickReplyItem
    let query: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.title)
                        .lineLimit(1)
                    Text(item.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(AttributedString(highlightedText(item.title, query: query, baseColor: NSColor.labelColor)))
                        .lineLimit(1)
                    Text(AttributedString(highlightedText(item.content, query: query, baseColor: NSColor.secondaryLabelColor)))
                        .font(.caption)
                        .lineLimit(1)
                }
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
        .padding(.vertical, 2)
    }

    private func highlightedText(_ text: String, query: String, baseColor: NSColor) -> NSAttributedString {
        HighlightRenderer.shared.render(text: text, itemID: item.id, query: query, baseColor: baseColor)
    }
}
