import EventKit
import Foundation

final class CalendarStore: @unchecked Sendable {
    private let store = EKEventStore()
    private let queue = DispatchQueue(label: "calendar-handler.eventkit")

    func accessStatus() -> AccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return AccessStatus(status: "notDetermined", readable: false, writable: false)
        case .restricted:
            return AccessStatus(status: "restricted", readable: false, writable: false)
        case .denied:
            return AccessStatus(status: "denied", readable: false, writable: false)
        case .fullAccess:
            return AccessStatus(status: "fullAccess", readable: true, writable: true)
        case .writeOnly:
            return AccessStatus(status: "writeOnly", readable: false, writable: true)
        @unknown default:
            return AccessStatus(status: "unknown", readable: false, writable: false)
        }
    }

    func requestFullAccess() throws -> AccessStatus {
        let semaphore = DispatchSemaphore(value: 0)
        let result = AccessRequestResult()
        store.requestFullAccessToEvents { didGrant, error in
            result.granted = didGrant
            result.error = error
            semaphore.signal()
        }
        semaphore.wait()
        if let requestError = result.error {
            throw requestError
        }
        if !result.granted {
            throw AppError.unauthorized("Calendar access was not granted")
        }
        store.reset()
        return accessStatus()
    }

    func requireReadable() throws {
        guard accessStatus().readable else {
            throw AppError.unauthorized("Full Calendar access is required")
        }
    }

    func calendars(query: String? = nil) throws -> [CalendarSummary] {
        try requireReadable()
        return queue.sync {
            filteredCalendars(query: query).map(calendarSummary)
        }
    }

    func events(since: Date, until: Date, calendarID: String?, calendarQuery: String?, limit: Int, offset: Int) throws -> [CalendarEventDTO] {
        try requireReadable()
        return queue.sync {
            let calendars = filteredCalendars(calendarID: calendarID, query: calendarQuery)
            let predicate = store.predicateForEvents(withStart: since, end: until, calendars: calendars)
            let rows = store.events(matching: predicate)
                .sorted { left, right in
                    if left.startDate == right.startDate {
                        return left.title < right.title
                    }
                    return left.startDate < right.startDate
                }
            return rows.dropFirst(max(0, offset)).prefix(limit).map(eventDTO)
        }
    }

    func search(query: String, since: Date, until: Date, calendarID: String?, calendarQuery: String?, limit: Int, offset: Int) throws -> [CalendarEventDTO] {
        let terms = searchTerms(query)
        guard !terms.isEmpty else {
            throw AppError.badRequest("query must include at least one search term")
        }
        let candidates = try events(since: since, until: until, calendarID: calendarID, calendarQuery: calendarQuery, limit: 10_000, offset: 0)
        let scored = candidates.compactMap { event -> CalendarEventDTO? in
            let score = scoreEvent(event, terms: terms)
            guard score > 0 else {
                return nil
            }
            return CalendarEventDTO(
                id: event.id,
                calendarID: event.calendarID,
                calendarTitle: event.calendarTitle,
                title: event.title,
                start: event.start,
                end: event.end,
                isAllDay: event.isAllDay,
                location: event.location,
                notes: event.notes,
                url: event.url,
                attendees: event.attendees,
                searchScore: score
            )
        }
        return scored
            .sorted {
                if $0.searchScore == $1.searchScore {
                    return $0.start < $1.start
                }
                return ($0.searchScore ?? 0) > ($1.searchScore ?? 0)
            }
            .dropFirst(max(0, offset))
            .prefix(limit)
            .map { $0 }
    }

    func event(id: String) throws -> CalendarEventDTO {
        try requireReadable()
        return try queue.sync {
            guard let event = store.event(withIdentifier: id) else {
                throw AppError.notFound("event not found")
            }
            return eventDTO(event)
        }
    }

    func freeTime(since: Date, until: Date, calendarID: String?, calendarQuery: String?, durationMinutes: Int, limit: Int) throws -> [FreeTimeSlot] {
        let busyEvents = try events(since: since, until: until, calendarID: calendarID, calendarQuery: calendarQuery, limit: 10_000, offset: 0)
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }

        var cursor = since
        var slots: [FreeTimeSlot] = []
        let required = TimeInterval(max(1, durationMinutes) * 60)

        for event in busyEvents {
            if event.start.timeIntervalSince(cursor) >= required {
                slots.append(slot(start: cursor, end: event.start))
                if slots.count >= limit {
                    return slots
                }
            }
            if event.end > cursor {
                cursor = event.end
            }
        }

        if until.timeIntervalSince(cursor) >= required {
            slots.append(slot(start: cursor, end: until))
        }
        return Array(slots.prefix(limit))
    }

    func createEvent(_ request: CreateEventRequest) throws -> CalendarEventDTO {
        guard accessStatus().writable else {
            throw AppError.unauthorized("Calendar write access is required")
        }
        let start = try parseDateBoundary(request.start, useEndOfDay: false)
        let end = try parseDateBoundary(request.end, useEndOfDay: false)
        guard start < end else {
            throw AppError.badRequest("event start must be before end")
        }

        return try queue.sync {
            let event = EKEvent(eventStore: store)
            event.title = request.title
            event.startDate = start
            event.endDate = end
            event.isAllDay = request.isAllDay ?? false
            event.location = request.location
            event.notes = request.notes
            if let rawURL = request.url {
                event.url = URL(string: rawURL)
            }
            if let calendarID = request.calendarID, let calendar = store.calendar(withIdentifier: calendarID) {
                event.calendar = calendar
            } else if let calendar = store.defaultCalendarForNewEvents {
                event.calendar = calendar
            } else {
                throw AppError.server("no default calendar for new events")
            }
            try store.save(event, span: .thisEvent, commit: true)
            return eventDTO(event)
        }
    }

    private func filteredCalendars(calendarID: String? = nil, query: String? = nil) -> [EKCalendar] {
        let all = store.calendars(for: .event)
        let query = query?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { calendar in
            if let calendarID, calendar.calendarIdentifier != calendarID {
                return false
            }
            if let query, !query.isEmpty, !calendar.title.lowercased().contains(query) {
                return false
            }
            return true
        }
    }

    private func calendarSummary(_ calendar: EKCalendar) -> CalendarSummary {
        CalendarSummary(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            type: String(describing: calendar.type),
            sourceTitle: calendar.source.title,
            allowsContentModifications: calendar.allowsContentModifications,
            colorHex: calendar.cgColor.flatMap(hexColor)
        )
    }

    private func eventDTO(_ event: EKEvent) -> CalendarEventDTO {
        CalendarEventDTO(
            id: event.eventIdentifier,
            calendarID: event.calendar?.calendarIdentifier,
            calendarTitle: event.calendar?.title,
            title: event.title ?? "(untitled)",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString,
            attendees: event.attendees?.map { $0.name ?? $0.url.absoluteString } ?? [],
            searchScore: nil
        )
    }
}

private func slot(start: Date, end: Date) -> FreeTimeSlot {
    FreeTimeSlot(start: start, end: end, durationMinutes: Int(end.timeIntervalSince(start) / 60))
}

private func searchTerms(_ value: String) -> [String] {
    let parts = value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    var seen = Set<String>()
    return parts.filter { seen.insert($0).inserted }
}

private func scoreEvent(_ event: CalendarEventDTO, terms: [String]) -> Double {
    let fields: [(String?, Double)] = [
        (event.title, 5),
        (event.location, 2),
        (event.notes, 1),
        (event.calendarTitle, 1.5),
        (event.url, 1)
    ]
    return terms.reduce(0) { total, term in
        total + fields.reduce(0) { fieldTotal, field in
            guard let text = field.0?.lowercased(), text.contains(term) else {
                return fieldTotal
            }
            return fieldTotal + field.1
        }
    }
}

private func hexColor(_ color: CGColor) -> String? {
    guard let components = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
          components.count >= 3 else {
        return nil
    }
    let r = Int((components[0] * 255).rounded())
    let g = Int((components[1] * 255).rounded())
    let b = Int((components[2] * 255).rounded())
    return String(format: "#%02X%02X%02X", r, g, b)
}

private final class AccessRequestResult: @unchecked Sendable {
    var granted = false
    var error: Error?
}
