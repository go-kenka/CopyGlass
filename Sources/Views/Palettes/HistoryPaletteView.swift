import SwiftUI
import AppKit

struct HistoryPaletteView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var model: HistoryPaletteModel
    let onPick: (UUID) -> Void
    let onCancel: () -> Void
    @Environment(\.appLanguage) private var lang
    @State private var queryTaskID = UUID()
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text(L10n.t(.history, lang: lang))
                        .font(.headline)
                    Spacer()
                    SearchField(text: $model.query, placeholder: L10n.t(.search, lang: lang))
                        .frame(width: 220)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                
                Divider()
                
                ScrollViewReader { proxy in
                    List(selection: $model.selectedID) {
                        ForEach(model.items) { item in
                            HistoryPaletteRow(
                                item: item,
                                query: model.query,
                                isSelected: model.selectedID == item.id
                            )
                                .id(item.id)
                                .tag(item.id)
                                .onTapGesture(count: 2) {
                                    onPick(item.id)
                                }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .onChange(of: model.selectedID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.08)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .onAppear {
            updateItemsForQuery()
            model.ensureSelection()
        }
        .onChange(of: clipboardManager.history) { _, _ in
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
        let taskID = UUID()
        queryTaskID = taskID
        DispatchQueue.global(qos: .userInitiated).async {
            let results = ClipboardItemStore.shared.searchSummaries(query: q, limit: 500)
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

struct HistoryPaletteRow: View {
    let item: ClipboardItemSummary
    let query: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
            
            if item.type == .image, let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: isSelected ? 132 : 96, height: isSelected ? 84 : 60)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(item.previewText ?? "")
                            .lineLimit(isSelected ? 3 : 1)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(AttributedString(highlightedText(item.previewText ?? "", query: query)))
                            .lineLimit(isSelected ? 3 : 1)
                            .multilineTextAlignment(.leading)
                    }
                    
                    if isSelected {
                        Text(item.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer(minLength: 0)
            if !isSelected {
                Text(item.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, isSelected ? 8 : 4)
    }
    
    private var iconName: String {
        switch item.type {
        case .text, .rtf: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
    
    private var image: NSImage? {
        guard let data = item.thumbnailData else { return nil }
        return NSImage(data: data)
    }
    
    private func highlightedText(_ text: String, query: String) -> NSAttributedString {
        HighlightRenderer.shared.render(text: text, itemID: item.id, query: query, baseColor: nil)
    }
}
