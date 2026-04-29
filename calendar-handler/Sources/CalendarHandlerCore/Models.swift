import Foundation

public struct CalendarSummary: Codable, Sendable {
    let id: String
    let title: String
    let type: String
    let sourceTitle: String?
    let allowsContentModifications: Bool
    let colorHex: String?
}

public struct CalendarEventDTO: Codable, Sendable {
    let id: String
    let calendarID: String?
    let calendarTitle: String?
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: String?
    let attendees: [String]
    let searchScore: Double?
}

public struct FreeTimeSlot: Codable, Sendable {
    let start: Date
    let end: Date
    let durationMinutes: Int
}

public struct AccessStatus: Codable, Sendable {
    let status: String
    let readable: Bool
    let writable: Bool
}

struct CreateEventRequest: Decodable {
    let title: String
    let start: String
    let end: String
    let calendarID: String?
    let location: String?
    let notes: String?
    let url: String?
    let isAllDay: Bool?
}
