import Foundation

do {
    let config = try Config.load()
    let source = try MessageSourceStore(path: config.messagesDBPath)
    let index = try IndexStore(path: config.indexDBPath)
    let indexer = Indexer(source: source, index: index)
    let contactsSync = ContactsSync()
    let api = API(config: config, source: source, index: index, indexer: indexer, contactsSync: contactsSync)
    let scheduler = SyncScheduler(
        indexer: indexer,
        messagesDBPath: config.messagesDBPath,
        interval: config.syncIntervalSeconds
    )

    scheduler.start()
    indexer.scheduleSync()

    let server = HTTPServer(host: config.host, port: config.port, handler: api.handle)
    try server.start()
} catch {
    fputs("fatal: \(error.localizedDescription)\n", stderr)
    exit(1)
}
