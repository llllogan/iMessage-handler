import Foundation

struct DateRange {
    let since: Date
    let until: Date
}

func dateRangeParam(_ query: [String: String], defaultLookaheadDays: Int) throws -> DateRange {
    let now = Date()
    let since = try firstNonEmpty(query["since"], query["from"], query["start"])
        .map { try parseDateBoundary($0, useEndOfDay: false) } ?? now
    let until = try firstNonEmpty(query["until"], query["to"], query["end"])
        .map { try parseDateBoundary($0, useEndOfDay: true) }
        ?? Calendar.current.date(byAdding: .day, value: defaultLookaheadDays, to: now)!

    guard since <= until else {
        throw AppError.badRequest("since must be before until")
    }
    return DateRange(since: since, until: until)
}

func parseDateBoundary(_ raw: String, useEndOfDay: Bool) throws -> Date {
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

func firstNonEmpty(_ values: String?...) -> String? {
    for value in values {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}

func intParam(_ query: [String: String], _ name: String, defaultValue: Int, maxValue: Int = 1_000) -> Int {
    guard let raw = query[name], let value = Int(raw), value > 0 else {
        return defaultValue
    }
    return min(value, maxValue)
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
