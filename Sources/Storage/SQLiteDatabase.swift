import Foundation
import SQLite3

enum SQLiteDatabaseError: Error {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDatabase {
    private var db: OpaquePointer?
    
    init(url: URL) throws {
        var ptr: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(url.path, &ptr, flags, nil)
        guard rc == SQLITE_OK, let ptr else {
            let msg = ptr.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite open failed"
            throw SQLiteDatabaseError.openFailed(msg)
        }
        db = ptr
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA foreign_keys=ON;")
    }
    
    deinit {
        if let db {
            sqlite3_close(db)
        }
    }
    
    func exec(_ sql: String) throws {
        guard let db else { return }
        var err: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(err)
            throw SQLiteDatabaseError.execFailed(msg)
        }
    }
    
    func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let db else { throw SQLiteDatabaseError.prepareFailed("db closed") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw SQLiteDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return SQLiteStatement(stmt: stmt)
    }
    
    func lastErrorMessage() -> String {
        guard let db else { return "db closed" }
        return String(cString: sqlite3_errmsg(db))
    }
    
    func userVersion() throws -> Int32 {
        let stmt = try prepare("PRAGMA user_version;")
        defer { stmt.reset() }
        guard stmt.step() == SQLITE_ROW else { return 0 }
        return Int32(stmt.columnInt64(0))
    }
    
    func setUserVersion(_ version: Int32) throws {
        try exec("PRAGMA user_version = \(version);")
    }
}

final class SQLiteStatement {
    fileprivate let stmt: OpaquePointer
    
    init(stmt: OpaquePointer) {
        self.stmt = stmt
    }
    
    deinit {
        sqlite3_finalize(stmt)
    }
    
    func reset() {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }
    
    func bindText(_ value: String?, index: Int32) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
    
    func bindDouble(_ value: Double, index: Int32) {
        sqlite3_bind_double(stmt, index, value)
    }
    
    func bindInt(_ value: Int64, index: Int32) {
        sqlite3_bind_int64(stmt, index, value)
    }
    
    func bindData(_ value: Data?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        _ = value.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
    }
    
    func step() -> Int32 {
        sqlite3_step(stmt)
    }
    
    func columnText(_ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
    
    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }
    
    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }
    
    func columnData(_ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let len = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: len)
    }
}
