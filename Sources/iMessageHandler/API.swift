import Foundation

final class API: @unchecked Sendable {
    private let config: Config
    private let source: MessageSourceStore
    private let index: IndexStore
    private let indexer: Indexer
    private let contactsSync: ContactsSync

    init(config: Config, source: MessageSourceStore, index: IndexStore, indexer: Indexer, contactsSync: ContactsSync) {
        self.config = config
        self.source = source
        self.index = index
        self.indexer = indexer
        self.contactsSync = contactsSync
    }

    func handle(_ request: HTTPRequest) throws -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/healthz"):
            return try HTTPResponse.json(["ok": true])

        case ("GET", "/api/messages/count"):
            return try HTTPResponse.json(["count": try source.messageCount()])

        case ("GET", "/api/messages/recent"):
            let limit = intParam(request, "limit", defaultValue: 5)
            return try HTTPResponse.json(["messages": try index.recentMessages(limit: limit)])

        case ("GET", "/api/messages/search"):
            let person = firstNonEmpty(request.query["person"], request.query["with"], request.query["name"])
            let phrase = firstNonEmpty(request.query["phrase"], request.query["query"], request.query["q"])
            let limit = intParam(request, "limit", defaultValue: 50)
            let offset = intParam(request, "offset", defaultValue: 0)
            if let phrase {
                return try HTTPResponse.json([
                    "messages": try index.search(query: phrase, participantQuery: person, limit: limit, offset: offset)
                ])
            }
            return try HTTPResponse.json([
                "messages": try index.messages(with: person, limit: limit, offset: offset)
            ])

        case ("GET", let path) where path.hasPrefix("/api/messages/") && path.hasSuffix("/context"):
            let id = try idFromPath(path, prefix: "/api/messages/", suffix: "/context")
            let before = intParam(request, "before", defaultValue: 10)
            let after = intParam(request, "after", defaultValue: 10)
            guard let context = try index.messageContext(id: id, before: before, after: after) else {
                throw AppError.notFound("message not found")
            }
            return try HTTPResponse.json(context)

        case ("GET", let path) where path.hasPrefix("/api/messages/"):
            let id = try idFromPath(path, prefix: "/api/messages/")
            guard let message = try index.message(id: id) else {
                throw AppError.notFound("message not found")
            }
            return try HTTPResponse.json(message)

        case ("GET", "/api/messages"):
            let limit = intParam(request, "limit", defaultValue: 50)
            let offset = intParam(request, "offset", defaultValue: 0)
            return try HTTPResponse.json([
                "messages": try index.messages(with: request.query["with"], limit: limit, offset: offset)
            ])

        case ("GET", "/api/timeline"):
            let limit = intParam(request, "limit", defaultValue: 100)
            let offset = intParam(request, "offset", defaultValue: 0)
            return try HTTPResponse.json([
                "messages": try index.timeline(
                    since: dateParam(request, "since"),
                    until: dateParam(request, "until"),
                    limit: limit,
                    offset: offset
                )
            ])

        case ("GET", "/api/chats"):
            let limit = intParam(request, "limit", defaultValue: 50)
            let offset = intParam(request, "offset", defaultValue: 0)
            return try HTTPResponse.json([
                "chats": try index.chats(query: request.query["query"], limit: limit, offset: offset)
            ])

        case ("GET", let path) where path.hasPrefix("/api/chats/") && path.hasSuffix("/messages"):
            let chatID = try idFromPath(path, prefix: "/api/chats/", suffix: "/messages")
            let limit = intParam(request, "limit", defaultValue: 50)
            let offset = intParam(request, "offset", defaultValue: 0)
            return try HTTPResponse.json([
                "messages": try index.messages(chatID: chatID, limit: limit, before: dateParam(request, "before"), offset: offset)
            ])

        case ("GET", let path) where path.hasPrefix("/api/chats/") && path.hasSuffix("/summary"):
            let chatID = try idFromPath(path, prefix: "/api/chats/", suffix: "/summary")
            guard let summary = try index.chatSummary(chatID: chatID) else {
                throw AppError.notFound("chat not found")
            }
            return try HTTPResponse.json(summary)

        case ("GET", "/api/participants"):
            let limit = intParam(request, "limit", defaultValue: 50)
            let offset = intParam(request, "offset", defaultValue: 0)
            return try HTTPResponse.json([
                "participants": try index.participants(query: request.query["query"], limit: limit, offset: offset)
            ])

        case ("GET", "/api/people"):
            let limit = intParam(request, "limit", defaultValue: 50)
            let offset = intParam(request, "offset", defaultValue: 0)
            return try HTTPResponse.json([
                "people": try index.contacts(query: request.query["query"], limit: limit, offset: offset)
            ])

        case ("POST", "/api/contacts/sync"):
            let identities = try contactsSync.loadContacts()
            return try HTTPResponse.json(try index.replaceContacts(identities))

        case ("GET", "/api/search"):
            guard let query = request.query["query"], !query.isEmpty else {
                throw AppError.badRequest("query parameter is required")
            }
            let limit = intParam(request, "limit", defaultValue: 50)
            let offset = intParam(request, "offset", defaultValue: 0)
            return try HTTPResponse.json([
                "messages": try index.search(
                    query: query,
                    participantQuery: request.query["with"],
                    limit: limit,
                    offset: offset
                )
            ])

        case ("GET", "/api/index/status"):
            return try HTTPResponse.json(try indexer.status(sourceDBPath: config.messagesDBPath))

        case ("GET", "/api/index/stats"):
            return try HTTPResponse.json(try index.stats())

        case ("POST", "/api/index/sync"):
            return try HTTPResponse.json(try indexer.sync())

        case ("POST", "/api/index/rebuild"):
            return try HTTPResponse.json(try indexer.rebuild(), status: 202)

        default:
            throw AppError.notFound("route not found")
        }
    }
}

private func intParam(_ request: HTTPRequest, _ name: String, defaultValue: Int) -> Int {
    guard let raw = request.query[name], let value = Int(raw) else {
        return defaultValue
    }
    return value
}

private func dateParam(_ request: HTTPRequest, _ name: String) -> Date? {
    guard let raw = request.query[name], !raw.isEmpty else {
        return nil
    }
    return ISO8601DateFormatter().date(from: raw)
}

private func idFromPath(_ path: String, prefix: String, suffix: String = "") throws -> Int64 {
    guard path.hasPrefix(prefix), suffix.isEmpty || path.hasSuffix(suffix) else {
        throw AppError.notFound("route not found")
    }

    let withoutPrefix = String(path.dropFirst(prefix.count))
    let rawID = suffix.isEmpty ? withoutPrefix : String(withoutPrefix.dropLast(suffix.count))
    guard let id = Int64(rawID), id > 0 else {
        throw AppError.badRequest("invalid id in path")
    }
    return id
}

private func firstNonEmpty(_ values: String?...) -> String? {
    for value in values {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}
