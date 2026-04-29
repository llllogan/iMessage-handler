import DotEnv
import Foundation

public final class IMessageHandlerRuntime: @unchecked Sendable {
    private let config: Config
    private let source: MessageSourceStore
    private let index: IndexStore
    private let indexer: Indexer
    private let contactsSync: ContactsSync
    private let api: API
    private let scheduler: SyncScheduler
    private let server: HTTPServer
    private let lifecycleQueue = DispatchQueue(label: "imessage-handler.runtime")
    private var auxiliaryTasksStarted = false
    private var serverStarted = false

    public var listenURL: String {
        "http://\(config.host):\(config.port)"
    }

    public init(loadDotEnv: Bool = true) throws {
        if loadDotEnv {
            try Self.loadDotEnvIfPresent()
        }

        let config = try Config.load()
        let source = try MessageSourceStore(path: config.messagesDBPath)
        let index = try IndexStore(path: config.indexDBPath)
        let indexer = Indexer(source: source, index: index)
        let contactsSync = ContactsSync()
        let api = API(config: config, source: source, index: index, indexer: indexer)
        let scheduler = SyncScheduler(
            indexer: indexer,
            messagesDBPath: config.messagesDBPath,
            interval: config.syncIntervalSeconds
        )

        self.config = config
        self.source = source
        self.index = index
        self.indexer = indexer
        self.contactsSync = contactsSync
        self.api = api
        self.scheduler = scheduler
        self.server = HTTPServer(host: config.host, port: config.port, handler: api.handle)
    }

    public static func loadDotEnvIfPresent(path: String = ".env") throws {
        for candidate in dotEnvCandidatePaths(primaryPath: path) {
            if FileManager.default.fileExists(atPath: candidate) {
                try DotEnv.load(path: candidate, overwrite: false)
            }
        }
    }

    public func startBlocking() throws -> Never {
        startAuxiliaryTasks()
        try server.start()
    }

    public func startInBackground(onError: @escaping @Sendable (String) -> Void) {
        startAuxiliaryTasks()
        let shouldStart = lifecycleQueue.sync { () -> Bool in
            guard !serverStarted else {
                return false
            }
            serverStarted = true
            return true
        }

        guard shouldStart else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [server] in
            do {
                try server.start()
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    public func syncNow() throws -> String {
        let result = try indexer.sync()
        return "Indexed \(result.indexed) new messages. Total indexed: \(result.indexedMessageCount)."
    }

    public func rebuildIndex() throws -> String {
        let result = try indexer.rebuild()
        return "Rebuilt index with \(result.indexedMessageCount) messages."
    }

    public func statusText() -> String {
        do {
            let status = try indexer.status(sourceDBPath: config.messagesDBPath)
            return "Running on \(listenURL). Indexed \(status.indexedMessageCount) of \(status.sourceMessageCount) messages."
        } catch {
            return "Status unavailable: \(error.localizedDescription)"
        }
    }

    public func canReadMessagesDatabase() -> Bool {
        FileManager.default.isReadableFile(atPath: config.messagesDBPath)
    }

    private func startAuxiliaryTasks() {
        let shouldStart = lifecycleQueue.sync { () -> Bool in
            guard !auxiliaryTasksStarted else {
                return false
            }
            auxiliaryTasksStarted = true
            return true
        }

        guard shouldStart else {
            return
        }

        scheduler.start()
        indexer.scheduleSync()
        DispatchQueue.global(qos: .utility).async { [contactsSync, index] in
            do {
                let identities = try contactsSync.loadContacts()
                let result = try index.replaceContacts(identities)
                print("synced \(result.contacts) contacts (\(result.identities) identities)")
            } catch {
                fputs("contacts sync skipped: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    private static func dotEnvCandidatePaths(primaryPath: String) -> [String] {
        var paths = [primaryPath]
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            paths.append(appSupport.appendingPathComponent("imessage-handler/.env").path)
        }
        if let resourcePath = Bundle.main.resourceURL?.appendingPathComponent(".env").path {
            paths.append(resourcePath)
        }

        var seen = Set<String>()
        return paths.filter { path in
            guard !seen.contains(path) else {
                return false
            }
            seen.insert(path)
            return true
        }
    }
}
