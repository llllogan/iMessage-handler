import Foundation
import Testing
@testable import iMessageHandlerCore

struct IndexStoreSearchTests {
    @Test func rankedSearchUsesWeightedTerms() throws {
        let store = try temporaryIndexStore()
        try store.upsert([
            message(id: 1, text: "school pickup time is 3pm", date: Date(timeIntervalSince1970: 100)),
            message(id: 2, text: "school form is due tomorrow", date: Date(timeIntervalSince1970: 300)),
            message(id: 3, text: "pickup time changed again", date: Date(timeIntervalSince1970: 200))
        ])

        let ranked = try store.search(query: "school pickup time", participantQuery: nil, limit: 10, offset: 0)
        #expect(ranked.map(\.id) == [1, 3, 2])
        #expect(ranked.first?.searchScore != nil)

        let exact = try store.search(query: "school pickup time", participantQuery: nil, limit: 10, offset: 0, mode: .exact)
        #expect(exact.map(\.id) == [1])

        let all = try store.search(query: "school pickup time", participantQuery: nil, limit: 10, offset: 0, mode: .all)
        #expect(all.map(\.id) == [1])

        let any = try store.search(query: "school pickup time", participantQuery: nil, limit: 10, offset: 0, mode: .any)
        #expect(any.map(\.id) == [1, 3, 2])
    }
}

private func temporaryIndexStore() throws -> IndexStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("imessage-handler-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try IndexStore(path: directory.appendingPathComponent("index.sqlite").path)
}

private func message(id: Int64, text: String, date: Date) -> IndexedMessage {
    IndexedMessage(
        id: id,
        guid: "guid-\(id)",
        plainText: text,
        textSource: "test",
        isFromMe: false,
        service: "iMessage",
        handleID: id,
        handle: "+1000000000\(id)",
        contactName: nil,
        chatID: 1,
        chatGUID: "chat-guid",
        displayName: nil,
        chatIdentifier: nil,
        sentAt: date,
        indexedAt: date,
        searchScore: nil
    )
}
