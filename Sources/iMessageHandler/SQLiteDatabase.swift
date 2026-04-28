import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDatabase: @unchecked Sendable {
    private let db: OpaquePointer?

    init(path: String, readOnly: Bool) throws {
        var handle: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(handle)
            throw AppError.database("open \(path): \(message)")
        }

        db = handle
        try exec("PRAGMA busy_timeout = 5000")
        if !readOnly {
            try exec("PRAGMA journal_mode = WAL")
            try exec("PRAGMA foreign_keys = ON")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw AppError.database(message)
        }
    }

    func query<T>(_ sql: String, _ bindings: [SQLiteValue] = [], map: (SQLiteStatement) throws -> T) throws -> [T] {
        let statement = try prepare(sql, bindings)
        defer { statement.finalize() }

        var rows: [T] = []
        while true {
            let code = sqlite3_step(statement.raw)
            if code == SQLITE_ROW {
                rows.append(try map(statement))
            } else if code == SQLITE_DONE {
                return rows
            } else {
                throw AppError.database(lastError)
            }
        }
    }

    func scalarInt64(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> Int64 {
        let rows = try query(sql, bindings) { statement in
            statement.int64(0)
        }
        return rows.first ?? 0
    }

    func execute(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, bindings)
        defer { statement.finalize() }

        let code = sqlite3_step(statement.raw)
        guard code == SQLITE_DONE else {
            throw AppError.database(lastError)
        }
    }

    func transaction(_ work: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try work()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ bindings: [SQLiteValue]) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw AppError.database(lastError)
        }
        let wrapped = SQLiteStatement(raw: statement, database: self)
        try wrapped.bind(bindings)
        return wrapped
    }

    fileprivate var lastError: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
    }
}

enum SQLiteValue {
    case int64(Int64)
    case int(Int)
    case text(String)
    case data(Data)
    case null
}

final class SQLiteStatement {
    fileprivate let raw: OpaquePointer?
    private let database: SQLiteDatabase

    fileprivate init(raw: OpaquePointer?, database: SQLiteDatabase) {
        self.raw = raw
        self.database = database
    }

    fileprivate func finalize() {
        sqlite3_finalize(raw)
    }

    fileprivate func bind(_ values: [SQLiteValue]) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let code: Int32
            switch value {
            case .int64(let value):
                code = sqlite3_bind_int64(raw, position, value)
            case .int(let value):
                code = sqlite3_bind_int(raw, position, Int32(value))
            case .text(let value):
                code = sqlite3_bind_text(raw, position, value, -1, sqliteTransient)
            case .data(let data):
                code = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(raw, position, buffer.baseAddress, Int32(data.count), sqliteTransient)
                }
            case .null:
                code = sqlite3_bind_null(raw, position)
            }
            if code != SQLITE_OK {
                throw AppError.database(database.lastError)
            }
        }
    }

    func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(raw, column)
    }

    func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int(raw, column))
    }

    func bool(_ column: Int32) -> Bool {
        int(column) != 0
    }

    func string(_ column: Int32) -> String? {
        guard let text = sqlite3_column_text(raw, column) else {
            return nil
        }
        return String(cString: text)
    }

    func data(_ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(raw, column) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(raw, column))
        return Data(bytes: bytes, count: count)
    }
}
