import Foundation

struct QuickReplyItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var content: String
    var shortcut: String?
    var category: String?
}
