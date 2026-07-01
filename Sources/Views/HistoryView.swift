import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    var searchText: String
    
    var filteredHistory: [ClipboardItemSummary] {
        if searchText.isEmpty {
            return clipboardManager.history
        } else {
            return clipboardManager.history.filter { item in
                item.previewText?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredHistory) { item in
                HistoryItemRow(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture { copyItem(item) }
            }
        }
        .listStyle(.inset)
        .detailSurface()
    }
    
    private func copyItem(_ item: ClipboardItemSummary) {
        guard clipboardManager.copyToPasteboard(id: item.id) else { return }
        PasteboardHelper.showCopySuccessToast()
        NSApp.hide(nil)

        // 恢复之前的应用（如果有）
        PasteboardHelper.restorePreviousApp()
    }
}

struct HistoryItemRow: View {
    let item: ClipboardItemSummary
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 4) {
                RichTextPreview(item: item)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text(HistoryDateFormatter.string(from: item.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .interactiveListRow()
    }
    
    var iconName: String {
        switch item.type {
        case .text, .rtf: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

struct RichTextPreview: View {
    let item: ClipboardItemSummary
    
    var body: some View {
        if item.type == .image, let data = item.thumbnailData, let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 44)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if let content = item.previewText, !content.isEmpty {
            Text(content)
        } else {
            Text(item.type == .image ? "Image" : "Item")
                .foregroundStyle(.secondary)
        }
    }
}
