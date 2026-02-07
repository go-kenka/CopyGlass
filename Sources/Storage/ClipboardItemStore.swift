import Foundation
import AppKit
import SQLite3

final class ClipboardItemStore {
    static let shared = ClipboardItemStore()
    
    private let db = AppDatabase.shared
    
    private init() {}
    
    func fetchRecent(limit: Int) -> [ClipboardItem] {
        do {
            return try db.read { db in
                let stmt = try db.prepare("""
                SELECT id, type, content, rtf, image, date, appBundleID
                FROM clipboard_items
                ORDER BY date DESC
                LIMIT ?;
                """)
                defer { stmt.reset() }
                stmt.bindInt(Int64(limit), index: 1)
                
                var items: [ClipboardItem] = []
                while stmt.step() == SQLITE_ROW {
                    let id = UUID(uuidString: stmt.columnText(0) ?? "") ?? UUID()
                    let type = ClipboardType(rawValue: stmt.columnText(1) ?? "text") ?? .text
                    let content = stmt.columnText(2)
                    let rtf = stmt.columnData(3)
                    let image = stmt.columnData(4)
                    let date = Date(timeIntervalSince1970: stmt.columnDouble(5))
                    let bundleID = stmt.columnText(6)
                    items.append(ClipboardItem(id: id, type: type, content: content, rtfData: rtf, imageData: image, date: date, appBundleID: bundleID))
                }
                return items
            }
        } catch {
            return []
        }
    }
    
    func fetchRecentSummaries(limit: Int) -> [ClipboardItemSummary] {
        do {
            return try db.read { db in
                let stmt = try db.prepare("""
                SELECT id, type, content_preview, image_thumb, date, appBundleID
                FROM clipboard_items
                ORDER BY date DESC
                LIMIT ?;
                """)
                defer { stmt.reset() }
                stmt.bindInt(Int64(limit), index: 1)
                
                var items: [ClipboardItemSummary] = []
                while stmt.step() == SQLITE_ROW {
                    let id = UUID(uuidString: stmt.columnText(0) ?? "") ?? UUID()
                    let type = ClipboardType(rawValue: stmt.columnText(1) ?? "text") ?? .text
                    let preview = stmt.columnText(2)
                    let thumb = stmt.columnData(3)
                    let date = Date(timeIntervalSince1970: stmt.columnDouble(4))
                    let bundleID = stmt.columnText(5)
                    items.append(ClipboardItemSummary(id: id, type: type, previewText: preview, thumbnailData: thumb, date: date, appBundleID: bundleID))
                }
                return items
            }
        } catch {
            return []
        }
    }

    func fetch(id: UUID) -> ClipboardItem? {
        do {
            return try db.read { db in
                let stmt = try db.prepare("""
                SELECT id, type, content, rtf, image, date, appBundleID
                FROM clipboard_items
                WHERE id = ?
                LIMIT 1;
                """)
                defer { stmt.reset() }
                stmt.bindText(id.uuidString, index: 1)
                guard stmt.step() == SQLITE_ROW else { return nil }
                let id = UUID(uuidString: stmt.columnText(0) ?? "") ?? UUID()
                let type = ClipboardType(rawValue: stmt.columnText(1) ?? "text") ?? .text
                let content = stmt.columnText(2)
                let rtf = stmt.columnData(3)
                let image = stmt.columnData(4)
                let date = Date(timeIntervalSince1970: stmt.columnDouble(5))
                let bundleID = stmt.columnText(6)
                return ClipboardItem(id: id, type: type, content: content, rtfData: rtf, imageData: image, date: date, appBundleID: bundleID)
            }
        } catch {
            return nil
        }
    }

    func search(query: String, limit: Int) -> [ClipboardItem] {
        let q = query.normalizedSearchText()
        if q.isEmpty { return fetchRecent(limit: limit) }
        let like = "%\(q)%"
        do {
            return try db.read { db in
                let stmt = try db.prepare("""
                SELECT id, type, content, rtf, image, date, appBundleID
                FROM clipboard_items
                WHERE (search_base LIKE ? ESCAPE '\\')
                   OR (search_pinyin LIKE ? ESCAPE '\\')
                ORDER BY date DESC
                LIMIT ?;
                """)
                defer { stmt.reset() }
                stmt.bindText(like, index: 1)
                stmt.bindText(like, index: 2)
                stmt.bindInt(Int64(limit), index: 3)

                var items: [ClipboardItem] = []
                while stmt.step() == SQLITE_ROW {
                    let id = UUID(uuidString: stmt.columnText(0) ?? "") ?? UUID()
                    let type = ClipboardType(rawValue: stmt.columnText(1) ?? "text") ?? .text
                    let content = stmt.columnText(2)
                    let rtf = stmt.columnData(3)
                    let image = stmt.columnData(4)
                    let date = Date(timeIntervalSince1970: stmt.columnDouble(5))
                    let bundleID = stmt.columnText(6)
                    items.append(ClipboardItem(id: id, type: type, content: content, rtfData: rtf, imageData: image, date: date, appBundleID: bundleID))
                }
                return items
            }
        } catch {
            return []
        }
    }
    
    func searchSummaries(query: String, limit: Int) -> [ClipboardItemSummary] {
        let q = query.normalizedSearchText()
        if q.isEmpty { return fetchRecentSummaries(limit: limit) }
        let like = "%\(q)%"
        do {
            return try db.read { db in
                let stmt = try db.prepare("""
                SELECT id, type, content_preview, image_thumb, date, appBundleID
                FROM clipboard_items
                WHERE (search_base LIKE ? ESCAPE '\\')
                   OR (search_pinyin LIKE ? ESCAPE '\\')
                ORDER BY date DESC
                LIMIT ?;
                """)
                defer { stmt.reset() }
                stmt.bindText(like, index: 1)
                stmt.bindText(like, index: 2)
                stmt.bindInt(Int64(limit), index: 3)
                
                var items: [ClipboardItemSummary] = []
                while stmt.step() == SQLITE_ROW {
                    let id = UUID(uuidString: stmt.columnText(0) ?? "") ?? UUID()
                    let type = ClipboardType(rawValue: stmt.columnText(1) ?? "text") ?? .text
                    let preview = stmt.columnText(2)
                    let thumb = stmt.columnData(3)
                    let date = Date(timeIntervalSince1970: stmt.columnDouble(4))
                    let bundleID = stmt.columnText(5)
                    items.append(ClipboardItemSummary(id: id, type: type, previewText: preview, thumbnailData: thumb, date: date, appBundleID: bundleID))
                }
                return items
            }
        } catch {
            return []
        }
    }
    
    func upsert(_ item: ClipboardItem) {
        let text = item.content ?? item.displayText
        let searchBase = text.normalizedSearchText()
        let searchPinyin = text.pinyinSearchText()
        let preview = makePreview(text: text)
        let thumb = makeThumbnailData(item: item)
        db.write({ db in
            let stmt = try db.prepare("""
            INSERT INTO clipboard_items (id, type, content, content_preview, rtf, image, image_thumb, date, appBundleID, search_base, search_pinyin)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type=excluded.type,
                content=excluded.content,
                content_preview=excluded.content_preview,
                rtf=excluded.rtf,
                image=excluded.image,
                image_thumb=excluded.image_thumb,
                date=excluded.date,
                appBundleID=excluded.appBundleID,
                search_base=excluded.search_base,
                search_pinyin=excluded.search_pinyin;
            """)
            defer { stmt.reset() }
            stmt.bindText(item.id.uuidString, index: 1)
            stmt.bindText(item.type.rawValue, index: 2)
            stmt.bindText(item.content, index: 3)
            stmt.bindText(preview, index: 4)
            stmt.bindData(item.rtfData, index: 5)
            stmt.bindData(item.imageData, index: 6)
            stmt.bindData(thumb, index: 7)
            stmt.bindDouble(item.date.timeIntervalSince1970, index: 8)
            stmt.bindText(item.appBundleID, index: 9)
            stmt.bindText(searchBase, index: 10)
            stmt.bindText(searchPinyin, index: 11)
            _ = stmt.step()
            return ()
        })
    }
    
    private func makePreview(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let collapsed = trimmed
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let limit = 360
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit))
    }
    
    private func makeThumbnailData(item: ClipboardItem) -> Data? {
        guard item.type == .image, let data = item.imageData, let image = NSImage(data: data) else { return nil }
        guard let rep = bestRepresentation(for: image) else { return nil }
        
        let maxSide: CGFloat = 256
        let w = CGFloat(rep.pixelsWide)
        let h = CGFloat(rep.pixelsHigh)
        if w <= 0 || h <= 0 { return nil }
        
        let scale = min(maxSide / w, maxSide / h, 1)
        let target = NSSize(width: floor(w * scale), height: floor(h * scale))
        let thumb = NSImage(size: target)
        thumb.lockFocusFlipped(false)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        thumb.unlockFocus()
        
        guard let tiff = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
    
    private func bestRepresentation(for image: NSImage) -> NSImageRep? {
        if let rep = image.representations.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }) {
            return rep
        }
        return nil
    }
    
    func prune(keep limit: Int) {
        db.write({ db in
            try db.exec("""
            DELETE FROM clipboard_items
            WHERE id NOT IN (
                SELECT id FROM clipboard_items
                ORDER BY date DESC
                LIMIT \(limit)
            );
            """)
            return ()
        })
    }
    
    func clear() {
        db.write({ db in
            try db.exec("DELETE FROM clipboard_items;")
            return ()
        })
    }
    
    func isEmpty() -> Bool {
        (try? db.read { db in
            let stmt = try db.prepare("SELECT COUNT(1) FROM clipboard_items;")
            defer { stmt.reset() }
            guard stmt.step() == SQLITE_ROW else { return true }
            return stmt.columnInt64(0) == 0
        }) ?? true
    }
}
