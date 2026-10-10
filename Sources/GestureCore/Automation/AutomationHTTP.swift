#if DEBUG
import Foundation

/// The little HTTP the automation's server speaks, enough for `curl` and a
/// shell script: one request a connection, its body as long as its
/// `Content-Length` says, and one answer, after which the connection
/// closes. Its parsing is a value, so a request that arrives in pieces is
/// read again as each comes, and tests feed it any split.
@_spi(GestureAutomation)
public struct AutomationHTTPRequest: Sendable, Equatable {
    /// The request's method, uppercased: "GET", "POST".
    public let method: String
    /// Its path, without its query: "/", "/state".
    public let path: String
    /// Its headers, by their lowercased names.
    public let headers: [String: String]
    /// Its body.
    public let body: Data

    /// The largest body a request may have: a command is a few hundred
    /// bytes, so anything near this is a mistake.
    public static let largestBody = 1 << 20

    /// What the bytes so far come to.
    public enum Reading: Sendable, Equatable {
        /// A whole request.
        case complete(AutomationHTTPRequest)
        /// Not all of it yet: read more.
        case incomplete
        /// Not a request it can answer, and why.
        case malformed(String)
    }

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// Reads `data`, the bytes a connection has sent so far.
    public static func read(_ data: Data) -> Reading {
        let separator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: separator) else {
            return data.count > 16 * 1024 ? .malformed("Its headers never ended.") : .incomplete
        }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .malformed("Its first line isn't a request.") }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length: Int
        if let given = headers["content-length"] {
            guard let number = Int(given), number >= 0 else { return .malformed("Its Content-Length isn't a number.") }
            length = number
        } else {
            length = 0
        }
        guard length <= largestBody else { return .malformed("Its body is longer than a command could be.") }
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]
        var path = String(requestLine[1])
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        return .complete(AutomationHTTPRequest(method: requestLine[0].uppercased(), path: path, headers: headers, body: Data(body)))
    }
}

/// An answer the automation's server sends: a status and a JSON body.
@_spi(GestureAutomation)
public struct AutomationHTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    /// An answer of `json`, pretty printed, with `status`.
    public init(status: Int = 200, json: AutomationJSON) {
        var body = json.encoded(pretty: true)
        body.append(contentsOf: Array("\n".utf8))
        self.init(status: status, body: body)
    }

    /// The bytes sent: the status line, the headers, which close the
    /// connection after it, and the body.
    public var bytes: Data {
        let reason = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
        var data = Data("""
            HTTP/1.1 \(status) \(reason)\r
            Content-Type: application/json\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r

            """.utf8)
        data.append(body)
        return data
    }
}
#endif
