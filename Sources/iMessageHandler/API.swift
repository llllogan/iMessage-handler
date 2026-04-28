import Foundation

final class API: @unchecked Sendable {
    private let config: Config
    private let source: MessageSourceStore
    private let index: IndexStore
    private let indexer: Indexer

    init(config: Config, source: MessageSourceStore, index: IndexStore, indexer: Indexer) {
        self.config = config
        self.source = source
        self.index = index
        self.indexer = indexer
    }

    func handle(_ request: HTTPRequest) throws -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/healthz"):
            return try HTTPResponse.json(["ok": true])

        case ("GET", "/api/messages/count"):
            return try HTTPResponse.json(["count": try source.messageCount()])

        case ("GET", "/api/messages/search"):
            let person = firstNonEmpty(request.query["person"], request.query["with"], request.query["name"])
            let phrase = firstNonEmpty(request.query["phrase"], request.query["query"], request.query["q"])
            guard person != nil || phrase != nil else {
                throw AppError.badRequest("person or phrase parameter is required")
            }
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
