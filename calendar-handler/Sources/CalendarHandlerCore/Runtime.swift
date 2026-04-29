import Foundation

public final class CalendarHandlerRuntime: @unchecked Sendable {
    private let config: Config
    private let calendarStore: CalendarStore
    private let api: API
    private let server: HTTPServer
    private let lifecycleQueue = DispatchQueue(label: "calendar-handler.runtime")
    private var serverStarted = false

    public var listenURL: String {
        "http://\(config.host):\(config.port)"
    }

    public init(loadDotEnv: Bool = true) throws {
        if loadDotEnv {
            try DotEnv.loadIfPresent()
        }
        let config = Config.load()
        let calendarStore = CalendarStore()
        let api = API(config: config, calendarStore: calendarStore)
        self.config = config
        self.calendarStore = calendarStore
        self.api = api
        self.server = HTTPServer(host: config.host, port: config.port, handler: api.handle)
    }

    public func startBlocking() throws -> Never {
        try server.start()
    }

    public func startInBackground(onError: @escaping @Sendable (String) -> Void) {
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

    public func requestAccess() throws -> String {
        let status = try calendarStore.requestFullAccess()
        return "Calendar access: \(status.status)"
    }

    public func requestAccessIfNotDetermined() throws -> String {
        let status = calendarStore.accessStatus()
        guard status.status == "notDetermined" else {
            return "Calendar access: \(status.status)"
        }
        return try requestAccess()
    }

    public func statusText() -> String {
        let status = calendarStore.accessStatus()
        return "Running on \(listenURL). Calendar access: \(status.status)."
    }
}
