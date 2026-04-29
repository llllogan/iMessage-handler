import Foundation

struct Config {
    let host: String
    let port: UInt16
    let messagesDBPath: String
    let indexDBPath: String
    let syncIntervalSeconds: TimeInterval
    let apiToken: String?

    static func load() throws -> Config {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let messagesDBPath = expandHome(env["IMESSAGE_DB_PATH"] ?? "~/Library/Messages/chat.db", home: home)
        let defaultIndexPath = try defaultIndexDBPath()

        return Config(
            host: env["IMESSAGE_HOST"] ?? "127.0.0.1",
            port: UInt16(env["IMESSAGE_PORT"] ?? "8080") ?? 8080,
            messagesDBPath: messagesDBPath,
            indexDBPath: expandHome(env["IMESSAGE_INDEX_DB_PATH"] ?? defaultIndexPath, home: home),
            syncIntervalSeconds: TimeInterval(env["IMESSAGE_SYNC_INTERVAL_SECONDS"] ?? "30") ?? 30,
            apiToken: nonEmpty(env["IMESSAGE_API_TOKEN"])
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func expandHome(_ path: String, home: String) -> String {
        if path == "~" {
            return home
        }
        if path.hasPrefix("~/") {
            return home + "/" + path.dropFirst(2)
        }
        return path
    }

    private static func defaultIndexDBPath() throws -> String {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("imessage-handler", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("index.sqlite").path
    }
}
