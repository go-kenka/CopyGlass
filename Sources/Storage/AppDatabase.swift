import Foundation

final class AppDatabase {
    static let shared = AppDatabase()
    
    private let queue = DispatchQueue(label: "copyglass.db", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private let expectedSchemaVersion: Int32 = 4
    private let db: SQLiteDatabase
    
    private init() {
        queue.setSpecific(key: queueKey, value: ())
        let url = AppPaths.applicationSupportDirectory().appendingPathComponent("copyglass.sqlite")
        let fm = FileManager.default
        
        if fm.fileExists(atPath: url.path) {
            do {
                let probe = try SQLiteDatabase(url: url)
                let version = (try? probe.userVersion()) ?? 0
                if version > expectedSchemaVersion {
                    try? fm.removeItem(at: url)
                }
            } catch {
                try? fm.removeItem(at: url)
            }
        }
        
        db = try! SQLiteDatabase(url: url)
        try! setupSchema()
    }
    
    func read<T>(_ block: (SQLiteDatabase) throws -> T) rethrows -> T {
        try block(db)
    }
    
    func write<T>(_ block: @escaping (SQLiteDatabase) throws -> T, completion: ((Result<T, Error>) -> Void)? = nil) {
        queue.async {
            do {
                let value = try block(self.db)
                completion?(.success(value))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    func writeAndWait<T>(_ block: (SQLiteDatabase) throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try block(db)
        }
        return try queue.sync {
            try block(db)
        }
    }
    
    private func setupSchema() throws {
        let currentVersion = (try? db.userVersion()) ?? 0
        try db.exec("""
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            content TEXT,
            content_preview TEXT,
            rtf BLOB,
            image BLOB,
            image_thumb BLOB,
            date REAL NOT NULL,
            appBundleID TEXT,
            search_base TEXT,
            search_pinyin TEXT
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_clipboard_items_date ON clipboard_items(date DESC);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_clipboard_items_search_base ON clipboard_items(search_base);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_clipboard_items_search_pinyin ON clipboard_items(search_pinyin);")
        try db.exec(ClipboardItemStoreSQL.createFTSTable)
        try db.exec(ClipboardItemStoreSQL.createFTSInsertTrigger)
        try db.exec(ClipboardItemStoreSQL.createFTSDeleteTrigger)
        try db.exec(ClipboardItemStoreSQL.createFTSUpdateTrigger)
        if currentVersion < expectedSchemaVersion {
            try db.exec(ClipboardItemStoreSQL.rebuildFTS)
        }
        
        try db.exec("""
        CREATE TABLE IF NOT EXISTS quick_replies (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            shortcut TEXT,
            category TEXT,
            search_base TEXT,
            search_pinyin TEXT
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_quick_replies_search_base ON quick_replies(search_base);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_quick_replies_search_pinyin ON quick_replies(search_pinyin);")
        
        try db.setUserVersion(expectedSchemaVersion)
    }
}
