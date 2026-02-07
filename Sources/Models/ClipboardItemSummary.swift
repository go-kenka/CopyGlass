import Foundation

struct ClipboardItemSummary: Identifiable, Hashable {
    var id: UUID
    var type: ClipboardType
    var previewText: String?
    var thumbnailData: Data?
    var date: Date
    var appBundleID: String?
}

