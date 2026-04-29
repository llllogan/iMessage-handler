import Darwin
import Foundation

typealias Handler = @Sendable (HTTPRequest) throws -> HTTPResponse

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    let status: Int
    let body: Data
    let contentType: String

    static func json<T: Encodable>(_ value: T, status: Int = 200) throws -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return HTTPResponse(status: status, body: try encoder.encode(value), contentType: "application/json")
    }
}

final class HTTPServer: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let handler: Handler

    init(host: String, port: UInt16, handler: @escaping Handler) {
        self.host = host
        self.port = port
        self.handler = handler
    }

    func start() throws -> Never {
        let serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw AppError.server("socket failed")
        }

        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr(host)

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverSocket)
            throw AppError.server("bind \(host):\(port) failed")
        }

        guard listen(serverSocket, SOMAXCONN) == 0 else {
            close(serverSocket)
            throw AppError.server("listen failed")
        }

        print("listening on http://\(host):\(port)")
        while true {
            let client = accept(serverSocket, nil, nil)
            guard client >= 0 else {
                continue
            }
            DispatchQueue.global().async { [handler] in
                handleClient(client, handler: handler)
            }
        }
    }
}

private func handleClient(_ fd: Int32, handler: Handler) {
    defer { close(fd) }

    let response: HTTPResponse
    do {
        let request = try readRequest(fd)
        response = try handler(request)
    } catch let error as AppError {
        response = errorResponse(error.localizedDescription, status: error.statusCode)
    } catch {
        response = errorResponse(error.localizedDescription, status: 500)
    }

    var payload = Data()
    payload.append("HTTP/1.1 \(response.status) \(reasonPhrase(response.status))\r\n".data(using: .utf8)!)
    payload.append("Content-Type: \(response.contentType)\r\n".data(using: .utf8)!)
    payload.append("Content-Length: \(response.body.count)\r\n".data(using: .utf8)!)
    payload.append("Connection: close\r\n\r\n".data(using: .utf8)!)
    payload.append(response.body)
    _ = payload.withUnsafeBytes { send(fd, $0.baseAddress, payload.count, 0) }
}

private func readRequest(_ fd: Int32) throws -> HTTPRequest {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 32_768)
    while true {
        let bytesRead = recv(fd, &buffer, buffer.count, 0)
        guard bytesRead > 0 else {
            break
        }
        data.append(buffer, count: Int(bytesRead))
        if let request = try parseRequestIfComplete(data) {
            return request
        }
        if data.count > 1_000_000 {
            throw AppError.badRequest("request too large")
        }
    }
    throw AppError.badRequest("invalid http request")
}

private func parseRequestIfComplete(_ data: Data) throws -> HTTPRequest? {
    guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
        return nil
    }
    let headerData = data[..<headerEnd.lowerBound]
    guard let rawHeaders = String(data: headerData, encoding: .utf8),
          let requestLine = rawHeaders.components(separatedBy: "\r\n").first else {
        throw AppError.badRequest("invalid http request")
    }

    let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else {
        throw AppError.badRequest("invalid request line")
    }

    var headers: [String: String] = [:]
    for line in rawHeaders.components(separatedBy: "\r\n").dropFirst() {
        let fields = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard fields.count == 2 else {
            continue
        }
        headers[fields[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
            fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let contentLength = Int(headers["content-length"] ?? "0") ?? 0
    let bodyStart = headerEnd.upperBound
    guard data.count >= bodyStart + contentLength else {
        return nil
    }

    guard let components = URLComponents(string: parts[1]) else {
        throw AppError.badRequest("invalid request target")
    }

    var query: [String: String] = [:]
    for item in components.queryItems ?? [] {
        query[item.name] = item.value ?? ""
    }

    let body = data[bodyStart..<(bodyStart + contentLength)]
    return HTTPRequest(method: parts[0], path: components.path, query: query, headers: headers, body: Data(body))
}

private func errorResponse(_ message: String, status: Int) -> HTTPResponse {
    let body = (try? JSONEncoder().encode(["error": message])) ?? Data("{\"error\":\"unknown error\"}".utf8)
    return HTTPResponse(status: status, body: body, contentType: "application/json")
}

private func reasonPhrase(_ status: Int) -> String {
    switch status {
    case 200: "OK"
    case 201: "Created"
    case 400: "Bad Request"
    case 401: "Unauthorized"
    case 404: "Not Found"
    case 503: "Service Unavailable"
    default: "Internal Server Error"
    }
}
