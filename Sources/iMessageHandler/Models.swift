import Foundation

struct SourceMessage {
    let id: Int64
    let guid: String
    let text: String?
    let attributedBody: Data?
    let date: Int64
    let isFromMe: Bool
    let service: String?
    let handleID: Int64?
    let handle: String?
    let chatID: Int64?
    let chatGUID: String?
    let displayName: String?
    let chatIdentifier: String?
}

struct IndexedMessage: Codable {
    let id: Int64
    let guid: String
    let plainText: String
    let textSource: String
    let isFromMe: Bool
    let service: String?
    let handleID: Int64?
    let handle: String?
    let chatID: Int64?
    let chatGUID: String?
    let displayName: String?
    let chatIdentifier: String?
    let sentAt: Date?
    let indexedAt: Date
}

struct IndexStatus: Codable {
    let sourceMessageCount: Int64
    let indexedMessageCount: Int64
    let lastIndexedMessageID: Int64
    let indexDBPath: String
    let sourceDBPath: String
}

struct SyncResult: Codable {
    let indexed: Int
    let lastIndexedMessageID: Int64
    let indexedMessageCount: Int64
}

struct IndexStats: Codable {
    let total: Int64
    let emptyPlainText: Int64
    let byTextSource: [TextSourceCount]
}

struct TextSourceCount: Codable {
    let textSource: String
    let count: Int64
    let emptyPlainText: Int64
}

struct ChatSummary: Codable {
    let chatID: Int64
    let chatGUID: String?
    let chatIdentifier: String?
    let displayName: String?
    let messageCount: Int64
    let firstMessageAt: Date?
    let lastMessageAt: Date?
    let participants: [String]
}

struct ParticipantSummary: Codable {
    let handleID: Int64
    let handle: String
    let messageCount: Int64
    let firstMessageAt: Date?
    let lastMessageAt: Date?
    let chats: [ParticipantChat]
}

struct ParticipantChat: Codable {
    let chatID: Int64
    let displayName: String?
    let chatIdentifier: String?
}

struct MessageContext: Codable {
    let message: IndexedMessage
    let before: [IndexedMessage]
    let after: [IndexedMessage]
}

func appleDate(_ raw: Int64) -> Date? {
    guard raw != 0 else {
        return nil
    }
    let appleEpoch: TimeInterval = 978_307_200
    if raw > 1_000_000_000_000_000 {
        return Date(timeIntervalSince1970: appleEpoch + TimeInterval(raw) / 1_000_000_000)
    }
    return Date(timeIntervalSince1970: appleEpoch + TimeInterval(raw))
}
