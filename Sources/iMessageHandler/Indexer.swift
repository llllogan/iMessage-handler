import Foundation

final class Indexer: @unchecked Sendable {
    private let source: MessageSourceStore
    private let index: IndexStore
    private let decoder = AttributedBodyDecoder()
    private let queue = DispatchQueue(label: "imessage-handler.indexer")
    private let queueKey = DispatchSpecificKey<Bool>()

    init(source: MessageSourceStore, index: IndexStore) {
        self.source = source
        self.index = index
        queue.setSpecific(key: queueKey, value: true)
    }

    func status(sourceDBPath: String) throws -> IndexStatus {
        try onQueue {
            IndexStatus(
                sourceMessageCount: try source.messageCount(),
                indexedMessageCount: try index.indexedMessageCount(),
                lastIndexedMessageID: try index.lastIndexedMessageID(),
                indexDBPath: index.path,
                sourceDBPath: sourceDBPath
            )
        }
    }

    func sync(batchSize: Int = 5_000) throws -> SyncResult {
        try onQueue {
            var total = 0

            let recent = try source.recentSourceMessages(limit: 1_000).map(indexedMessage)
            try index.upsert(recent)

            while true {
                let lastID = try index.lastIndexedMessageID()
                let sourceMessages = try source.messages(afterID: lastID, limit: batchSize)
                if sourceMessages.isEmpty {
                    break
                }

                let indexed = sourceMessages.map(indexedMessage)
                try index.upsert(indexed)
                try index.setLastIndexedMessageID(sourceMessages.last?.id ?? lastID)
                total += indexed.count

                if sourceMessages.count < batchSize {
                    break
                }
            }

            return SyncResult(
                indexed: total,
                lastIndexedMessageID: try index.lastIndexedMessageID(),
                indexedMessageCount: try index.indexedMessageCount()
            )
        }
    }

    func rebuild(batchSize: Int = 5_000) throws -> SyncResult {
        try onQueue {
            try index.clear()
            var total = 0

            while true {
                let lastID = try index.lastIndexedMessageID()
                let sourceMessages = try source.messages(afterID: lastID, limit: batchSize)
                if sourceMessages.isEmpty {
                    break
                }
                let indexed = sourceMessages.map(indexedMessage)
                try index.upsert(indexed)
                try index.setLastIndexedMessageID(sourceMessages.last?.id ?? lastID)
                total += indexed.count
            }

            return SyncResult(
                indexed: total,
                lastIndexedMessageID: try index.lastIndexedMessageID(),
                indexedMessageCount: try index.indexedMessageCount()
            )
        }
    }

    func scheduleSync() {
        queue.async { [weak self] in
            do {
                _ = try self?.sync()
            } catch {
                fputs("sync failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    private func onQueue<T>(_ work: () throws -> T) throws -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            return try work()
        }
        return try queue.sync(execute: work)
    }

    private func indexedMessage(_ source: SourceMessage) -> IndexedMessage {
        let decoded = decoder.decode(text: source.text, attributedBody: source.attributedBody)
        return IndexedMessage(
            id: source.id,
            guid: source.guid,
            plainText: decoded.text,
            textSource: decoded.source,
            isFromMe: source.isFromMe,
            service: source.service,
            handleID: source.handleID,
            handle: source.handle,
            contactName: nil,
            chatID: source.chatID,
            chatGUID: source.chatGUID,
            displayName: source.displayName,
            chatIdentifier: source.chatIdentifier,
            sentAt: appleDate(source.date),
            indexedAt: Date()
        )
    }
}
