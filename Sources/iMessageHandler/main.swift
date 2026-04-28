import Foundation

do {
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

    scheduler.start()
    indexer.scheduleSync()
    DispatchQueue.global(qos: .utility).async {
        do {
            let identities = try contactsSync.loadContacts()
            let result = try index.replaceContacts(identities)
            print("synced \(result.contacts) contacts (\(result.identities) identities)")
        } catch {
            fputs("contacts sync skipped: \(error.localizedDescription)\n", stderr)
        }
    }

    let server = HTTPServer(host: config.host, port: config.port, handler: api.handle)
    try server.start()
} catch {
    fputs("fatal: \(error.localizedDescription)\n", stderr)
    exit(1)
}
