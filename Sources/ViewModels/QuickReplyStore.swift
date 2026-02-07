import Foundation
import AppKit

final class QuickReplyStore: ObservableObject {
    static let shared = QuickReplyStore()
    
    @Published var items: [QuickReplyItem] = []
    private let store = QuickReplyItemStore.shared
    
    private init() {
        items = store.fetchAll()
        if items.isEmpty {
            items = [
                QuickReplyItem(title: "Email", content: "my.email@example.com", shortcut: "cmd+1"),
                QuickReplyItem(title: "Address", content: "123 Apple Park Way, Cupertino, CA", shortcut: "cmd+2")
            ]
            items.forEach { store.upsert($0) }
        }
    }
    
    func add(_ item: QuickReplyItem) {
        items.append(item)
        store.upsert(item)
    }
    
    func delete(_ item: QuickReplyItem) {
        items.removeAll { $0.id == item.id }
        store.delete(id: item.id)
    }
    
    func copyToPasteboard(_ item: QuickReplyItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
    }
}
