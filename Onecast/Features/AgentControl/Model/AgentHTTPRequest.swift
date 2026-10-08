import Foundation

/// The one HTTP/1.1 shape the agent channel speaks: a request, one JSON reply, then close.
struct AgentHTTPRequest: Equatable, Sendable {
    enum Parse: Equatable, Sendable {
        case incomplete
        case malformed(String)
        case request(AgentHTTPRequest)
    }

    /// Bounds a client that never stops sending; no command needs more than a screenful of JSON.
    static let maximumBytes = 1 << 20

    let method: String
    let path: String
    /// Names lowercased, since HTTP header names are case-insensitive.
    let headers: [String: String]
    let body: Data

    var bearerToken: String? {
        guard let value = headers["authorization"] else { return nil }
        let prefix = "bearer "
        guard value.lowercased().hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ data: Data) -> Parse {
        guard data.count <= maximumBytes else { return .malformed("Request too large.") }
        guard let headEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return .incomplete
        }
        guard let head = String(bytes: data[data.startIndex..<headEnd.lowerBound], encoding: .utf8)
        else { return .malformed("Header is not UTF-8.") }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .malformed("Bad request line.")
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .malformed("Bad header.") }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = headers["content-length"].flatMap(Int.init) ?? 0
        guard length >= 0 else { return .malformed("Bad Content-Length.") }
        let bodyStart = headEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        return .request(
            AgentHTTPRequest(
                method: String(requestLine[0]), path: String(requestLine[1]), headers: headers,
                body: Data(data[bodyStart..<(bodyStart + length)])))
    }

    static func response(status: Int, body: Data) -> Data {
        let reason =
            switch status {
            case 200: "OK"
            case 400: "Bad Request"
            case 401: "Unauthorized"
            case 404: "Not Found"
            default: "Error"
            }
        let head =
            "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
