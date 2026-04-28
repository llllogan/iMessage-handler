import Foundation

final class IndexStore: @unchecked Sendable {
    private let db: SQLiteDatabase
    let path: String

    init(path: String) throws {
        self.path = path
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        db = try SQLiteDatabase(path: path, readOnly: false)
        try migrate()
    }

    func indexedMessageCount() throws -> Int64 {
        try db.scalarInt64("SELECT COUNT(*) FROM indexed_message")
    }

    func lastIndexedMessageID() throws -> Int64 {
        try db.scalarInt64("SELECT COALESCE((SELECT value FROM sync_state WHERE key = 'last_sequential_message_id'), 0)")
    }

    func stats() throws -> IndexStats {
        let rows = try db.query(
            """
            SELECT text_source, COUNT(*), SUM(CASE WHEN plain_text = '' THEN 1 ELSE 0 END)
            FROM indexed_message
            GROUP BY text_source
            ORDER BY COUNT(*) DESC
            """
        ) { statement in
            TextSourceCount(
                textSource: statement.string(0) ?? "",
                count: statement.int64(1),
                emptyPlainText: statement.int64(2)
            )
        }

        return IndexStats(
            total: try indexedMessageCount(),
            emptyPlainText: try db.scalarInt64("SELECT COUNT(*) FROM indexed_message WHERE plain_text = ''"),
            byTextSource: rows
        )
    }

    func setLastIndexedMessageID(_ id: Int64) throws {
        try db.execute(
            """
            INSERT INTO sync_state (key, value) VALUES ('last_sequential_message_id', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            [.int64(id)]
        )
    }

    func replaceContacts(_ identities: [ContactIdentity]) throws -> ContactSyncResult {
        try db.transaction {
            try db.exec("DELETE FROM contact_identity")
            for identity in identities {
                try db.execute(
                    """
                    INSERT OR REPLACE INTO contact_identity (
                        identity_value, kind, display_name, given_name, family_name, organization_name, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(identity.identityValue.lowercased()),
                        .text(identity.kind),
                        .text(identity.displayName),
                        optionalText(identity.givenName),
                        optionalText(identity.familyName),
                        optionalText(identity.organizationName),
                        .int64(Int64(Date().timeIntervalSince1970))
                    ]
                )
            }
        }

        return ContactSyncResult(
            contacts: Set(identities.map(\.displayName)).count,
            identities: identities.count
        )
    }

    func contacts(query: String?, limit: Int, offset: Int) throws -> [ContactIdentity] {
        let query = query ?? ""
        let pattern = likePattern(query)
        return try db.query(
            """
            SELECT identity_value, kind, display_name, given_name, family_name, organization_name
            FROM contact_identity
            WHERE
                ? = ''
                OR display_name LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR identity_value LIKE ? ESCAPE '\\' COLLATE NOCASE
            ORDER BY display_name, kind, identity_value
            LIMIT ? OFFSET ?
            """,
            [
                .text(query),
                .text(pattern),
                .text(pattern),
                .int(normalizeLimit(limit, defaultValue: 50)),
                .int(max(0, offset))
            ]
        ) { statement in
            ContactIdentity(
                identityValue: statement.string(0) ?? "",
                kind: statement.string(1) ?? "",
                displayName: statement.string(2) ?? "",
                givenName: statement.string(3),
                familyName: statement.string(4),
                organizationName: statement.string(5)
            )
        }
    }

    func clear() throws {
        try db.transaction {
            try db.exec("DELETE FROM indexed_message")
            try db.exec("INSERT INTO message_fts(message_fts) VALUES('rebuild')")
            try setLastIndexedMessageID(0)
        }
    }

    func upsert(_ messages: [IndexedMessage]) throws {
        guard !messages.isEmpty else {
            return
        }

        try db.transaction {
            for message in messages {
                try db.execute(
                    """
                    INSERT INTO indexed_message (
                        message_id, guid, date, is_from_me, service, handle_id, handle,
                        chat_id, chat_guid, chat_identifier, display_name, plain_text,
                        text_source, indexed_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(message_id) DO UPDATE SET
                        guid = excluded.guid,
                        date = excluded.date,
                        is_from_me = excluded.is_from_me,
                        service = excluded.service,
                        handle_id = excluded.handle_id,
                        handle = excluded.handle,
                        chat_id = excluded.chat_id,
                        chat_guid = excluded.chat_guid,
                        chat_identifier = excluded.chat_identifier,
                        display_name = excluded.display_name,
                        plain_text = excluded.plain_text,
                        text_source = excluded.text_source,
                        indexed_at = excluded.indexed_at
                    """,
                    [
                        .int64(message.id),
                        .text(message.guid),
                        .int64(message.sentAt.map { Int64($0.timeIntervalSince1970) } ?? 0),
                        .int(message.isFromMe ? 1 : 0),
                        optionalText(message.service),
                        optionalInt64(message.handleID),
                        optionalText(message.handle),
                        optionalInt64(message.chatID),
                        optionalText(message.chatGUID),
                        optionalText(message.chatIdentifier),
                        optionalText(message.displayName),
                        .text(message.plainText),
                        .text(message.textSource),
                        .int64(Int64(message.indexedAt.timeIntervalSince1970))
                    ]
                )
            }
        }
    }

    func recentMessages(limit: Int) throws -> [IndexedMessage] {
        try loadMessages(
            """
            SELECT message_id, guid, plain_text, text_source, is_from_me, service, handle_id,
                   handle, chat_id, chat_guid, display_name, chat_identifier, date, indexed_at,
                   (SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(indexed_message.handle) LIMIT 1)
            FROM indexed_message
            ORDER BY date DESC, message_id DESC
            LIMIT ?
            """,
            [.int(normalizeLimit(limit, defaultValue: 5))]
        )
    }

    func message(id: Int64) throws -> IndexedMessage? {
        try loadMessages(
            """
            SELECT message_id, guid, plain_text, text_source, is_from_me, service, handle_id,
                   handle, chat_id, chat_guid, display_name, chat_identifier, date, indexed_at,
                   (SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(indexed_message.handle) LIMIT 1)
            FROM indexed_message
            WHERE message_id = ?
            LIMIT 1
            """,
            [.int64(id)]
        ).first
    }

    func messageContext(id: Int64, before: Int, after: Int) throws -> MessageContext? {
        guard let message = try message(id: id) else {
            return nil
        }

        let beforeRows = try loadMessages(
            """
            SELECT message_id, guid, plain_text, text_source, is_from_me, service, handle_id,
                   handle, chat_id, chat_guid, display_name, chat_identifier, date, indexed_at,
                   (SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(indexed_message.handle) LIMIT 1)
            FROM indexed_message
            WHERE chat_id IS ? AND (date < ? OR (date = ? AND message_id < ?))
            ORDER BY date DESC, message_id DESC
            LIMIT ?
            """,
            [
                nullableInt64(message.chatID),
                .int64(unixTimestamp(message.sentAt)),
                .int64(unixTimestamp(message.sentAt)),
                .int64(message.id),
                .int(normalizeLimit(before, defaultValue: 10))
            ]
        ).reversed()

        let afterRows = try loadMessages(
            """
            SELECT message_id, guid, plain_text, text_source, is_from_me, service, handle_id,
                   handle, chat_id, chat_guid, display_name, chat_identifier, date, indexed_at,
                   (SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(indexed_message.handle) LIMIT 1)
            FROM indexed_message
            WHERE chat_id IS ? AND (date > ? OR (date = ? AND message_id > ?))
            ORDER BY date ASC, message_id ASC
            LIMIT ?
            """,
            [
                nullableInt64(message.chatID),
                .int64(unixTimestamp(message.sentAt)),
                .int64(unixTimestamp(message.sentAt)),
                .int64(message.id),
                .int(normalizeLimit(after, defaultValue: 10))
            ]
        )

        return MessageContext(message: message, before: Array(beforeRows), after: afterRows)
    }

    func messages(with participantQuery: String?, limit: Int, offset: Int) throws -> [IndexedMessage] {
        let query = participantQuery ?? ""
        let pattern = likePattern(query)
        return try loadMessages(
            """
            SELECT message_id, guid, plain_text, text_source, is_from_me, service, handle_id,
                   handle, chat_id, chat_guid, display_name, chat_identifier, date, indexed_at,
                   (SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(indexed_message.handle) LIMIT 1)
            FROM indexed_message
            WHERE
                ? = ''
                OR handle LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR EXISTS (
                    SELECT 1 FROM contact_identity ci
                    WHERE ci.identity_value = lower(indexed_message.handle)
                      AND ci.display_name LIKE ? ESCAPE '\\' COLLATE NOCASE
                )
                OR display_name LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR chat_identifier LIKE ? ESCAPE '\\' COLLATE NOCASE
            ORDER BY date DESC, message_id DESC
            LIMIT ? OFFSET ?
            """,
            [
                .text(query),
                .text(pattern),
                .text(pattern),
                .text(pattern),
                .text(pattern),
                .int(normalizeLimit(limit, defaultValue: 50)),
                .int(max(0, offset))
            ]
        )
    }

    func messages(chatID: Int64, limit: Int, before: Date?, offset: Int) throws -> [IndexedMessage] {
        let beforeTimestamp = before.map { Int64($0.timeIntervalSince1970) } ?? Int64.max
        return try loadMessages(
            """
            SELECT message_id, guid, plain_text, text_source, is_from_me, service, handle_id,
                   handle, chat_id, chat_guid, display_name, chat_identifier, date, indexed_at,
                   (SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(indexed_message.handle) LIMIT 1)
            FROM indexed_message
            WHERE chat_id = ? AND date < ?
            ORDER BY date DESC, message_id DESC
            LIMIT ? OFFSET ?
            """,
            [
                .int64(chatID),
                .int64(beforeTimestamp),
                .int(normalizeLimit(limit, defaultValue: 50)),
                .int(max(0, offset))
            ]
        )
    }

    func timeline(since: Date?, until: Date?, limit: Int, offset: Int) throws -> [IndexedMessage] {
        let sinceTimestamp = since.map { Int64($0.timeIntervalSince1970) } ?? 0
        let untilTimestamp = until.map { Int64($0.timeIntervalSince1970) } ?? Int64.max
        return try loadMessages(
            """
            SELECT message_id, guid, plain_text, text_source, is_from_me, service, handle_id,
                   handle, chat_id, chat_guid, display_name, chat_identifier, date, indexed_at,
                   (SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(indexed_message.handle) LIMIT 1)
            FROM indexed_message
            WHERE date >= ? AND date <= ?
            ORDER BY date DESC, message_id DESC
            LIMIT ? OFFSET ?
            """,
            [
                .int64(sinceTimestamp),
                .int64(untilTimestamp),
                .int(normalizeLimit(limit, defaultValue: 100)),
                .int(max(0, offset))
            ]
        )
    }

    func search(query: String, participantQuery: String?, limit: Int, offset: Int) throws -> [IndexedMessage] {
        let participantQuery = participantQuery ?? ""
        let pattern = likePattern(participantQuery)
        return try loadMessages(
            """
            SELECT im.message_id, im.guid, im.plain_text, im.text_source, im.is_from_me, im.service,
                   im.handle_id, im.handle, im.chat_id, im.chat_guid, im.display_name,
                   im.chat_identifier, im.date, im.indexed_at,
                   (SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(im.handle) LIMIT 1)
            FROM message_fts fts
            JOIN indexed_message im ON im.message_id = fts.rowid
            WHERE message_fts MATCH ?
              AND (
                ? = ''
                OR im.handle LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR EXISTS (
                    SELECT 1 FROM contact_identity ci
                    WHERE ci.identity_value = lower(im.handle)
                      AND ci.display_name LIKE ? ESCAPE '\\' COLLATE NOCASE
                )
                OR im.display_name LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR im.chat_identifier LIKE ? ESCAPE '\\' COLLATE NOCASE
              )
            ORDER BY im.date DESC, im.message_id DESC
            LIMIT ? OFFSET ?
            """,
            [
                .text(ftsPhrase(query)),
                .text(participantQuery),
                .text(pattern),
                .text(pattern),
                .text(pattern),
                .text(pattern),
                .int(normalizeLimit(limit, defaultValue: 50)),
                .int(max(0, offset))
            ]
        )
    }

    func chats(query: String?, limit: Int, offset: Int) throws -> [ChatSummary] {
        let query = query ?? ""
        let pattern = likePattern(query)
        let rows = try db.query(
            """
            SELECT
                chat_id,
                MAX(chat_guid),
                MAX(chat_identifier),
                MAX(display_name),
                COUNT(*),
                MIN(date),
                MAX(date),
                COALESCE(group_concat(DISTINCT handle), '')
            FROM indexed_message
            WHERE chat_id IS NOT NULL
              AND (
                ? = ''
                OR display_name LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR chat_identifier LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR handle LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR EXISTS (
                    SELECT 1 FROM contact_identity ci
                    WHERE ci.identity_value = lower(indexed_message.handle)
                      AND ci.display_name LIKE ? ESCAPE '\\' COLLATE NOCASE
                )
              )
            GROUP BY chat_id
            ORDER BY MAX(date) DESC
            LIMIT ? OFFSET ?
            """,
            [
                .text(query),
                .text(pattern),
                .text(pattern),
                .text(pattern),
                .text(pattern),
                .int(normalizeLimit(limit, defaultValue: 50)),
                .int(max(0, offset))
            ]
        ) { statement in
            ChatSummary(
                chatID: statement.int64(0),
                chatGUID: statement.string(1),
                chatIdentifier: statement.string(2),
                displayName: statement.string(3),
                messageCount: statement.int64(4),
                firstMessageAt: unixDate(statement.int64(5)),
                lastMessageAt: unixDate(statement.int64(6)),
                participants: splitList(statement.string(7))
            )
        }
        return rows
    }

    func chatSummary(chatID: Int64) throws -> ChatSummary? {
        try chatsForIDs([chatID]).first
    }

    func participants(query: String?, limit: Int, offset: Int) throws -> [ParticipantSummary] {
        let query = query ?? ""
        let pattern = likePattern(query)
        return try db.query(
            """
            SELECT
                handle_id,
                MAX(handle),
                MAX((SELECT ci.display_name FROM contact_identity ci WHERE ci.identity_value = lower(indexed_message.handle) LIMIT 1)),
                COUNT(*),
                MIN(date),
                MAX(date),
                COALESCE(group_concat(DISTINCT (chat_id || char(31) || COALESCE(display_name, '') || char(31) || COALESCE(chat_identifier, ''))), '')
            FROM indexed_message
            WHERE handle_id IS NOT NULL
              AND handle IS NOT NULL
              AND (
                ? = ''
                OR handle LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR EXISTS (
                    SELECT 1 FROM contact_identity ci
                    WHERE ci.identity_value = lower(indexed_message.handle)
                      AND ci.display_name LIKE ? ESCAPE '\\' COLLATE NOCASE
                )
              )
            GROUP BY handle_id
            ORDER BY MAX(date) DESC
            LIMIT ? OFFSET ?
            """,
            [
                .text(query),
                .text(pattern),
                .text(pattern),
                .int(normalizeLimit(limit, defaultValue: 50)),
                .int(max(0, offset))
            ]
        ) { statement in
            ParticipantSummary(
                handleID: statement.int64(0),
                handle: statement.string(1) ?? "",
                contactName: statement.string(2),
                messageCount: statement.int64(3),
                firstMessageAt: unixDate(statement.int64(4)),
                lastMessageAt: unixDate(statement.int64(5)),
                chats: parseParticipantChats(statement.string(6))
            )
        }
    }

    private func chatsForIDs(_ ids: [Int64]) throws -> [ChatSummary] {
        guard !ids.isEmpty else {
            return []
        }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        return try db.query(
            """
            SELECT
                chat_id,
                MAX(chat_guid),
                MAX(chat_identifier),
                MAX(display_name),
                COUNT(*),
                MIN(date),
                MAX(date),
                COALESCE(group_concat(DISTINCT handle), '')
            FROM indexed_message
            WHERE chat_id IN (\(placeholders))
            GROUP BY chat_id
            ORDER BY MAX(date) DESC
            """,
            ids.map(SQLiteValue.int64)
        ) { statement in
            ChatSummary(
                chatID: statement.int64(0),
                chatGUID: statement.string(1),
                chatIdentifier: statement.string(2),
                displayName: statement.string(3),
                messageCount: statement.int64(4),
                firstMessageAt: unixDate(statement.int64(5)),
                lastMessageAt: unixDate(statement.int64(6)),
                participants: splitList(statement.string(7))
            )
        }
    }

    private func migrate() throws {
        try db.exec(
            """
            CREATE TABLE IF NOT EXISTS indexed_message (
                message_id INTEGER PRIMARY KEY,
                guid TEXT NOT NULL,
                date INTEGER NOT NULL,
                is_from_me INTEGER NOT NULL,
                service TEXT,
                handle_id INTEGER,
                handle TEXT,
                chat_id INTEGER,
                chat_guid TEXT,
                chat_identifier TEXT,
                display_name TEXT,
                plain_text TEXT NOT NULL,
                text_source TEXT NOT NULL,
                indexed_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sync_state (
                key TEXT PRIMARY KEY,
                value INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS contact_identity (
                identity_value TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                display_name TEXT NOT NULL,
                given_name TEXT,
                family_name TEXT,
                organization_name TEXT,
                updated_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS contact_identity_display_name_idx
            ON contact_identity(display_name);

            CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(
                plain_text,
                content='indexed_message',
                content_rowid='message_id',
                tokenize='unicode61'
            );

            CREATE TRIGGER IF NOT EXISTS indexed_message_ai AFTER INSERT ON indexed_message BEGIN
                INSERT INTO message_fts(rowid, plain_text) VALUES (new.message_id, new.plain_text);
            END;

            CREATE TRIGGER IF NOT EXISTS indexed_message_ad AFTER DELETE ON indexed_message BEGIN
                INSERT INTO message_fts(message_fts, rowid, plain_text) VALUES('delete', old.message_id, old.plain_text);
            END;

            CREATE TRIGGER IF NOT EXISTS indexed_message_au AFTER UPDATE ON indexed_message BEGIN
                INSERT INTO message_fts(message_fts, rowid, plain_text) VALUES('delete', old.message_id, old.plain_text);
                INSERT INTO message_fts(rowid, plain_text) VALUES (new.message_id, new.plain_text);
            END;
            """
        )
    }

    private func loadMessages(_ sql: String, _ bindings: [SQLiteValue]) throws -> [IndexedMessage] {
        try db.query(sql, bindings) { statement in
            IndexedMessage(
                id: statement.int64(0),
                guid: statement.string(1) ?? "",
                plainText: statement.string(2) ?? "",
                textSource: statement.string(3) ?? "",
                isFromMe: statement.bool(4),
                service: statement.string(5),
                handleID: optionalInt64(statement, 6),
                handle: statement.string(7),
                contactName: statement.string(14),
                chatID: optionalInt64(statement, 8),
                chatGUID: statement.string(9),
                displayName: statement.string(10),
                chatIdentifier: statement.string(11),
                sentAt: unixDate(statement.int64(12)),
                indexedAt: unixDate(statement.int64(13)) ?? Date(timeIntervalSince1970: 0)
            )
        }
    }
}

private func optionalText(_ value: String?) -> SQLiteValue {
    guard let value else {
        return .null
    }
    return .text(value)
}

private func optionalInt64(_ value: Int64?) -> SQLiteValue {
    guard let value else {
        return .null
    }
    return .int64(value)
}

private func nullableInt64(_ value: Int64?) -> SQLiteValue {
    guard let value else {
        return .null
    }
    return .int64(value)
}

private func optionalInt64(_ statement: SQLiteStatement, _ column: Int32) -> Int64? {
    let value = statement.int64(column)
    return value == 0 ? nil : value
}

private func unixDate(_ value: Int64) -> Date? {
    value == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(value))
}

private func unixTimestamp(_ value: Date?) -> Int64 {
    value.map { Int64($0.timeIntervalSince1970) } ?? 0
}

private func normalizeLimit(_ value: Int, defaultValue: Int) -> Int {
    if value <= 0 {
        return defaultValue
    }
    return min(value, 500)
}

private func ftsPhrase(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}

private func likePattern(_ value: String) -> String {
    guard !value.isEmpty else {
        return ""
    }
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%")
        .replacingOccurrences(of: "_", with: "\\_")
    return "%\(escaped)%"
}

private func splitList(_ value: String?) -> [String] {
    guard let value, !value.isEmpty else {
        return []
    }
    var seen = Set<String>()
    return value
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { item in
            guard !item.isEmpty, !seen.contains(item) else {
                return false
            }
            seen.insert(item)
            return true
        }
}

private func parseParticipantChats(_ value: String?) -> [ParticipantChat] {
    guard let value, !value.isEmpty else {
        return []
    }

    var seen = Set<Int64>()
    return value.split(separator: ",").compactMap { raw in
        let fields = raw.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3, let chatID = Int64(fields[0]), !seen.contains(chatID) else {
            return nil
        }
        seen.insert(chatID)
        return ParticipantChat(
            chatID: chatID,
            displayName: fields[1].isEmpty ? nil : fields[1],
            chatIdentifier: fields[2].isEmpty ? nil : fields[2]
        )
    }
}
