import Foundation

final class AppDatabase {
    static let shared = AppDatabase()
    
    private let queue = DispatchQueue(label: "copyglass.db", qos: .utility)
    private let expectedSchemaVersion: Int32 = 3
    private let db: SQLiteDatabase
    
    private init() {
        let url = AppPaths.applicationSupportDirectory().appendingPathComponent("copyglass.sqlite")
        let fm = FileManager.default
        
        if fm.fileExists(atPath: url.path) {
            do {
                let probe = try SQLiteDatabase(url: url)
                let version = (try? probe.userVersion()) ?? 0
                if version != expectedSchemaVersion {
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
    
    private func setupSchema() throws {
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
