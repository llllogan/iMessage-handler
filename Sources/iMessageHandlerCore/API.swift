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
        try authorize(request)

        switch (request.method, request.path) {
        case ("GET", "/healthz"):
            return try HTTPResponse.json(["ok": true])

        case ("GET", "/api/messages/count"):
            return try HTTPResponse.json(["count": try source.messageCount()])

        case ("GET", "/api/messages/search"):
            let person = firstNonEmpty(request.query["person"], request.query["with"], request.query["name"])
            let phrase = firstNonEmpty(request.query["phrase"], request.query["query"], request.query["q"])
            guard person != nil || phrase != nil else {
                let range = try dateRangeParam(request)
                guard range.since != nil || range.until != nil else {
                    throw AppError.badRequest("person, phrase, or date range parameter is required")
                }
                let limit = intParam(request, "limit", defaultValue: 50)
                let offset = intParam(request, "offset", defaultValue: 0)
                return try HTTPResponse.json([
                    "messages": try index.timeline(since: range.since, until: range.until, limit: limit, offset: offset)
                ])
            }
            let limit = intParam(request, "limit", defaultValue: 50)
            let offset = intParam(request, "offset", defaultValue: 0)
            let range = try dateRangeParam(request)
            let mode = try searchModeParam(request)
            if let phrase {
                return try HTTPResponse.json([
                    "messages": try index.search(
                        query: phrase,
                        participantQuery: person,
                        limit: limit,
                        offset: offset,
                        mode: mode,
                        since: range.since,
                        until: range.until
                    )
                ])
            }
            return try HTTPResponse.json([
                "messages": try index.messages(
                    with: person,
                    limit: limit,
                    offset: offset,
                    since: range.since,
                    until: range.until
                )
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

    private func authorize(_ request: HTTPRequest) throws {
        guard request.path.hasPrefix("/api/"), let token = config.apiToken else {
            return
        }
        let expected = "Bearer \(token)"
        guard request.headers["authorization"] == expected else {
            throw AppError.unauthorized("missing or invalid authorization token")
        }
    }
}

private struct DateRange {
    let since: Date?
    let until: Date?
}

enum SearchMode: String {
    case ranked
    case exact
    case all
    case any
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

private func searchModeParam(_ request: HTTPRequest) throws -> SearchMode {
    let raw = firstNonEmpty(request.query["mode"], request.query["searchMode"]) ?? SearchMode.ranked.rawValue
    guard let mode = SearchMode(rawValue: raw.lowercased()) else {
        throw AppError.badRequest("unsupported search mode: \(raw)")
    }
    return mode
}

private func dateRangeParam(_ request: HTTPRequest) throws -> DateRange {
    var range = try timeframeRange(request.query["timeframe"] ?? request.query["range"])

    if let raw = firstNonEmpty(
        request.query["since"],
        request.query["from"],
        request.query["start"],
        request.query["startDate"],
        request.query["after"]
    ) {
        range = DateRange(since: try parseDateBoundary(raw, useEndOfDay: false), until: range.until)
    }

    if let raw = firstNonEmpty(
        request.query["until"],
        request.query["to"],
        request.query["end"],
        request.query["endDate"],
        request.query["before"]
    ) {
        range = DateRange(since: range.since, until: try parseDateBoundary(raw, useEndOfDay: true))
    }

    if let since = range.since, let until = range.until, since > until {
        throw AppError.badRequest("since must be before until")
    }

    return range
}

private func timeframeRange(_ raw: String?) throws -> DateRange {
    guard let raw = firstNonEmpty(raw) else {
        return DateRange(since: nil, until: nil)
    }

    let key = raw.lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    let calendar = Calendar.current
    let now = Date()
    let today = calendar.startOfDay(for: now)

    switch key {
    case "today":
        return DateRange(since: today, until: endOfDay(today, calendar: calendar))
    case "yesterday":
        let start = calendar.date(byAdding: .day, value: -1, to: today)!
        return DateRange(since: start, until: endOfDay(start, calendar: calendar))
    case "this_week":
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            throw AppError.badRequest("could not compute this_week timeframe")
        }
        return DateRange(since: interval.start, until: now)
    case "last_week":
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start),
              let end = calendar.date(byAdding: .second, value: -1, to: thisWeek.start) else {
            throw AppError.badRequest("could not compute last_week timeframe")
        }
        return DateRange(since: start, until: end)
    case "this_month":
        guard let interval = calendar.dateInterval(of: .month, for: now) else {
            throw AppError.badRequest("could not compute this_month timeframe")
        }
        return DateRange(since: interval.start, until: now)
    case "last_month":
        guard let thisMonth = calendar.dateInterval(of: .month, for: now),
              let start = calendar.date(byAdding: .month, value: -1, to: thisMonth.start),
              let end = calendar.date(byAdding: .second, value: -1, to: thisMonth.start) else {
            throw AppError.badRequest("could not compute last_month timeframe")
        }
        return DateRange(since: start, until: end)
    case "last_7_days":
        return DateRange(since: calendar.date(byAdding: .day, value: -7, to: now), until: now)
    case "last_14_days":
        return DateRange(since: calendar.date(byAdding: .day, value: -14, to: now), until: now)
    case "last_30_days":
        return DateRange(since: calendar.date(byAdding: .day, value: -30, to: now), until: now)
    case "last_90_days":
        return DateRange(since: calendar.date(byAdding: .day, value: -90, to: now), until: now)
    default:
        throw AppError.badRequest("unsupported timeframe: \(raw)")
    }
}

private func parseDateBoundary(_ raw: String, useEndOfDay: Bool) throws -> Date {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let timestamp = TimeInterval(trimmed) {
        return Date(timeIntervalSince1970: timestamp)
    }

    if let date = isoDateTime(trimmed) {
        return date
    }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    if let date = formatter.date(from: trimmed) {
        return useEndOfDay ? endOfDay(date, calendar: formatter.calendar) : date
    }

    throw AppError.badRequest("invalid date: \(raw)")
}

private func isoDateTime(_ raw: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: raw) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw)
}

private func endOfDay(_ date: Date, calendar: Calendar) -> Date {
    let start = calendar.startOfDay(for: date)
    return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
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
