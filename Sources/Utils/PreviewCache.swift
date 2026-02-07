import Foundation
import AppKit

final class PreviewCache {
    static let shared = PreviewCache()
    
    private let imageCache = NSCache<NSString, NSImage>()
    private let rtfCache = NSCache<NSString, NSAttributedString>()
    
    private init() {
        imageCache.countLimit = 600
        rtfCache.countLimit = 600
    }
    
    func image(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image, let data = item.imageData else { return nil }
        let key = item.id.uuidString as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let img = NSImage(data: data) else { return nil }
        imageCache.setObject(img, forKey: key)
        return img
    }
    
    func rtfText(for item: ClipboardItem) -> NSAttributedString? {
        guard item.type == .rtf, let data = item.rtfData else { return nil }
        let key = item.id.uuidString as NSString
        if let cached = rtfCache.object(forKey: key) { return cached }
        guard let ns = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        rtfCache.setObject(ns, forKey: key)
        return ns
    }
}

