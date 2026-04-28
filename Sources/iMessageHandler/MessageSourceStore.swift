import Foundation

final class MessageSourceStore: @unchecked Sendable {
    private let db: SQLiteDatabase

    init(path: String) throws {
        db = try SQLiteDatabase(path: path, readOnly: true)
    }

    func messageCount() throws -> Int64 {
        try db.scalarInt64("SELECT COUNT(*) FROM message")
    }

    func messages(afterID id: Int64, limit: Int) throws -> [SourceMessage] {
        try queryMessages(
            whereClause: "m.ROWID > ?",
            bindings: [.int64(id)],
            order: "m.ROWID ASC",
            limit: limit
        )
    }

    func recentSourceMessages(limit: Int) throws -> [SourceMessage] {
        try queryMessages(
            whereClause: "1 = 1",
            bindings: [],
            order: "m.date DESC",
            limit: limit
        )
    }

    private func queryMessages(whereClause: String, bindings: [SQLiteValue], order: String, limit: Int) throws -> [SourceMessage] {
        let safeLimit = max(1, min(limit, 5_000))
        return try db.query(
            """
            SELECT DISTINCT
                m.ROWID,
                COALESCE(m.guid, ''),
                m.text,
                m.attributedBody,
                COALESCE(m.date, 0),
                COALESCE(m.is_from_me, 0),
                m.service,
                h.ROWID,
                h.id,
                c.ROWID,
                c.guid,
                c.display_name,
                c.chat_identifier
            FROM message m
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN chat c ON c.ROWID = cmj.chat_id
            WHERE \(whereClause)
            ORDER BY \(order)
            LIMIT ?
            """,
            bindings + [.int(safeLimit)]
        ) { statement in
            SourceMessage(
                id: statement.int64(0),
                guid: statement.string(1) ?? "",
                text: statement.string(2),
                attributedBody: statement.data(3),
                date: statement.int64(4),
                isFromMe: statement.bool(5),
                service: statement.string(6),
                handleID: optionalInt64(statement, 7),
                handle: statement.string(8),
                chatID: optionalInt64(statement, 9),
                chatGUID: statement.string(10),
                displayName: statement.string(11),
                chatIdentifier: statement.string(12)
            )
        }
    }
}

private func optionalInt64(_ statement: SQLiteStatement, _ column: Int32) -> Int64? {
    let value = statement.int64(column)
    return value == 0 ? nil : value
}
