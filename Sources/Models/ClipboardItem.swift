import Foundation
import AppKit

enum ClipboardType: String, Codable {
    case text
    case rtf
    case image
    case file
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: ClipboardType
    var content: String? // Plain text representation
    var rtfData: Data?   // Rich text data
    var imageData: Data? // Image data
    var date: Date
    var appBundleID: String?
    
    // Helper to get display text
    var displayText: String {
        return content ?? "Image/File"
    }
}
