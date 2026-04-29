import Foundation

final class API: @unchecked Sendable {
    private let config: Config
    private let calendarStore: CalendarStore

    init(config: Config, calendarStore: CalendarStore) {
        self.config = config
        self.calendarStore = calendarStore
    }

    func handle(_ request: HTTPRequest) throws -> HTTPResponse {
        try authorize(request)

        switch (request.method, request.path) {
        case ("GET", "/healthz"):
            return try HTTPResponse.json(["ok": true])

        case ("GET", "/api/access/status"):
            return try HTTPResponse.json(calendarStore.accessStatus())

        case ("POST", "/api/access/request"):
            return try HTTPResponse.json(try calendarStore.requestFullAccess())

        case ("GET", "/api/calendars"):
            return try HTTPResponse.json(["calendars": try calendarStore.calendars(query: request.query["query"])])

        case ("GET", "/api/events/range"):
            let range = try dateRangeParam(request.query, defaultLookaheadDays: config.defaultLookaheadDays)
            return try HTTPResponse.json([
                "events": try calendarStore.events(
                    since: range.since,
                    until: range.until,
                    calendarID: request.query["calendarID"],
                    calendarQuery: request.query["calendar"],
                    limit: intParam(request.query, "limit", defaultValue: 100),
                    offset: intParam(request.query, "offset", defaultValue: 0)
                )
            ])

        case ("GET", "/api/events/search"):
            guard let query = firstNonEmpty(request.query["query"], request.query["q"]) else {
                throw AppError.badRequest("query parameter is required")
            }
            let range = try dateRangeParam(request.query, defaultLookaheadDays: config.defaultLookaheadDays)
            return try HTTPResponse.json([
                "events": try calendarStore.search(
                    query: query,
                    since: range.since,
                    until: range.until,
                    calendarID: request.query["calendarID"],
                    calendarQuery: request.query["calendar"],
                    limit: intParam(request.query, "limit", defaultValue: 50),
                    offset: intParam(request.query, "offset", defaultValue: 0)
                )
            ])

        case ("GET", "/api/free-time"):
            let range = try dateRangeParam(request.query, defaultLookaheadDays: config.defaultLookaheadDays)
            return try HTTPResponse.json([
                "slots": try calendarStore.freeTime(
                    since: range.since,
                    until: range.until,
                    calendarID: request.query["calendarID"],
                    calendarQuery: request.query["calendar"],
                    durationMinutes: intParam(request.query, "durationMinutes", defaultValue: 30, maxValue: 24 * 60),
                    limit: intParam(request.query, "limit", defaultValue: 20, maxValue: 200)
                )
            ])

        case ("GET", let path) where path.hasPrefix("/api/events/"):
            let id = String(path.dropFirst("/api/events/".count)).removingPercentEncoding ?? ""
            guard !id.isEmpty else {
                throw AppError.badRequest("event id is required")
            }
            return try HTTPResponse.json(try calendarStore.event(id: id))

        case ("POST", "/api/events/create"):
            let decoder = JSONDecoder()
            let create = try decoder.decode(CreateEventRequest.self, from: request.body)
            return try HTTPResponse.json(try calendarStore.createEvent(create), status: 201)

        default:
            throw AppError.notFound("route not found")
        }
    }

    private func authorize(_ request: HTTPRequest) throws {
        guard request.path.hasPrefix("/api/"), let token = config.apiToken else {
            return
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            throw AppError.unauthorized("missing or invalid authorization token")
        }
    }
}
