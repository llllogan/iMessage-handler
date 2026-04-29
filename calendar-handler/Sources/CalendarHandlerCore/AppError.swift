import Foundation

public enum AppError: Error, LocalizedError {
    case badRequest(String)
    case notFound(String)
    case server(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case .badRequest(let message), .notFound(let message), .server(let message), .unauthorized(let message):
            return message
        }
    }

    var statusCode: Int {
        switch self {
        case .badRequest:
            return 400
        case .unauthorized:
            return 401
        case .notFound:
            return 404
        case .server:
            return 500
        }
    }
}
