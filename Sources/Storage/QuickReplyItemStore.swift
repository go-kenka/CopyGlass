import Foundation
import SQLite3

final class QuickReplyItemStore {
    static let shared = QuickReplyItemStore()
    
    private let db = AppDatabase.shared
    
    private init() {}
    
    func fetchAll() -> [QuickReplyItem] {
        do {
            return try db.read { db in
                let stmt = try db.prepare("""
                SELECT id, title, content, shortcut, category
                FROM quick_replies
                ORDER BY rowid ASC;
                """)
                defer { stmt.reset() }
                
                var items: [QuickReplyItem] = []
                while stmt.step() == SQLITE_ROW {
                    let id = UUID(uuidString: stmt.columnText(0) ?? "") ?? UUID()
                    let title = stmt.columnText(1) ?? ""
                    let content = stmt.columnText(2) ?? ""
                    let shortcut = stmt.columnText(3)
                    let category = stmt.columnText(4)
                    items.append(QuickReplyItem(id: id, title: title, content: content, shortcut: shortcut, category: category))
                }
                return items
            }
        } catch {
            return []
        }
    }

    func fetch(id: UUID) -> QuickReplyItem? {
        do {
            return try db.read { db in
                let stmt = try db.prepare("""
                SELECT id, title, content, shortcut, category
                FROM quick_replies
                WHERE id = ?
                LIMIT 1;
                """)
                defer { stmt.reset() }
                stmt.bindText(id.uuidString, index: 1)
                guard stmt.step() == SQLITE_ROW else { return nil }
                let id = UUID(uuidString: stmt.columnText(0) ?? "") ?? UUID()
                let title = stmt.columnText(1) ?? ""
                let content = stmt.columnText(2) ?? ""
                let shortcut = stmt.columnText(3)
                let category = stmt.columnText(4)
                return QuickReplyItem(id: id, title: title, content: content, shortcut: shortcut, category: category)
            }
        } catch {
            return nil
        }
    }

    func search(query: String, limit: Int) -> [QuickReplyItem] {
        let q = query.normalizedSearchText()
        if q.isEmpty { return fetchAll() }
        let like = "%\(q)%"
        do {
            return try db.read { db in
                let stmt = try db.prepare("""
                SELECT id, title, content, shortcut, category
                FROM quick_replies
                WHERE (search_base LIKE ? ESCAPE '\\')
                   OR (search_pinyin LIKE ? ESCAPE '\\')
                ORDER BY rowid ASC
                LIMIT ?;
                """)
                defer { stmt.reset() }
                stmt.bindText(like, index: 1)
                stmt.bindText(like, index: 2)
                stmt.bindInt(Int64(limit), index: 3)

                var items: [QuickReplyItem] = []
                while stmt.step() == SQLITE_ROW {
                    let id = UUID(uuidString: stmt.columnText(0) ?? "") ?? UUID()
                    let title = stmt.columnText(1) ?? ""
                    let content = stmt.columnText(2) ?? ""
                    let shortcut = stmt.columnText(3)
                    let category = stmt.columnText(4)
                    items.append(QuickReplyItem(id: id, title: title, content: content, shortcut: shortcut, category: category))
                }
                return items
            }
        } catch {
            return []
        }
    }
    
    func upsert(_ item: QuickReplyItem) {
        let combined = "\(item.title) \(item.content)"
        let searchBase = combined.normalizedSearchText()
        let searchPinyin = combined.pinyinSearchText()
        db.write({ db in
            let stmt = try db.prepare("""
            INSERT INTO quick_replies (id, title, content, shortcut, category, search_base, search_pinyin)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title,
                content=excluded.content,
                shortcut=excluded.shortcut,
                category=excluded.category,
                search_base=excluded.search_base,
                search_pinyin=excluded.search_pinyin;
            """)
            defer { stmt.reset() }
            stmt.bindText(item.id.uuidString, index: 1)
            stmt.bindText(item.title, index: 2)
            stmt.bindText(item.content, index: 3)
            stmt.bindText(item.shortcut, index: 4)
            stmt.bindText(item.category, index: 5)
            stmt.bindText(searchBase, index: 6)
            stmt.bindText(searchPinyin, index: 7)
            _ = stmt.step()
            return ()
        })
    }
    
    func delete(id: UUID) {
        db.write({ db in
            let stmt = try db.prepare("DELETE FROM quick_replies WHERE id = ?;")
            defer { stmt.reset() }
            stmt.bindText(id.uuidString, index: 1)
            _ = stmt.step()
            return ()
        })
    }
    
    func clear() {
        db.write({ db in
            try db.exec("DELETE FROM quick_replies;")
            return ()
        })
    }
    
    func isEmpty() -> Bool {
        (try? db.read { db in
            let stmt = try db.prepare("SELECT COUNT(1) FROM quick_replies;")
            defer { stmt.reset() }
            guard stmt.step() == SQLITE_ROW else { return true }
            return stmt.columnInt64(0) == 0
        }) ?? true
    }
}
