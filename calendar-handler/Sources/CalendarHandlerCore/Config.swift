import Foundation

public struct Config: Sendable {
    let host: String
    let port: UInt16
    let apiToken: String?
    let defaultLookaheadDays: Int

    public static func load() -> Config {
        let env = ProcessInfo.processInfo.environment
        return Config(
            host: env["CALENDAR_HOST"] ?? "127.0.0.1",
            port: UInt16(env["CALENDAR_PORT"] ?? "8090") ?? 8090,
            apiToken: nonEmpty(env["CALENDAR_API_TOKEN"]),
            defaultLookaheadDays: Int(env["CALENDAR_DEFAULT_LOOKAHEAD_DAYS"] ?? "90") ?? 90
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum DotEnv {
    public static func loadIfPresent(path: String = ".env") throws {
        for candidate in candidatePaths(primaryPath: path) where FileManager.default.fileExists(atPath: candidate) {
            try load(path: candidate)
        }
    }

    private static func load(path: String) throws {
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = unquote(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            setenv(key, value, 0)
        }
    }

    private static func candidatePaths(primaryPath: String) -> [String] {
        var paths = [primaryPath]
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            paths.append(appSupport.appendingPathComponent("calendar-handler/.env").path)
        }
        if let resourcePath = Bundle.main.resourceURL?.appendingPathComponent(".env").path {
            paths.append(resourcePath)
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private static func unquote(_ value: String) -> String {
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
