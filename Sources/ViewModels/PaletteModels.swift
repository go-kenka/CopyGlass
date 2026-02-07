import Foundation

final class HistoryPaletteModel: ObservableObject {
    @Published var query: String = ""
    @Published var selectedID: UUID?
    @Published var filteredIDs: [UUID] = []
    @Published var items: [ClipboardItemSummary] = []
    
    func moveSelection(delta: Int) {
        guard !filteredIDs.isEmpty else { return }
        let currentIndex = selectedID.flatMap { filteredIDs.firstIndex(of: $0) } ?? 0
        let next = max(0, min(filteredIDs.count - 1, currentIndex + delta))
        selectedID = filteredIDs[next]
    }
    
    func ensureSelection() {
        if selectedID == nil {
            selectedID = filteredIDs.first
        }
    }
    
    func resetSelectionToFirst() {
        selectedID = filteredIDs.first
    }
}

final class QuickReplyPaletteModel: ObservableObject {
    @Published var query: String = ""
    @Published var selectedID: QuickReplyItem.ID?
    @Published var filteredIDs: [QuickReplyItem.ID] = []
    @Published var items: [QuickReplyItem] = []
    
    func moveSelection(delta: Int) {
        guard !filteredIDs.isEmpty else { return }
        let currentIndex = selectedID.flatMap { filteredIDs.firstIndex(of: $0) } ?? 0
        let next = max(0, min(filteredIDs.count - 1, currentIndex + delta))
        selectedID = filteredIDs[next]
    }
    
    func ensureSelection() {
        if selectedID == nil {
            selectedID = filteredIDs.first
        }
    }
}
