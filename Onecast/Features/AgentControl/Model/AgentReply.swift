import Foundation

/// The reply envelope: `{"ok": true, "result": …}` or `{"ok": false, "error": "…"}`.
enum AgentReply {
    private struct Success<Result: Encodable>: Encodable {
        let ok = true
        let result: Result
    }

    private struct Failure: Encodable {
        let ok = false
        let error: String
    }

    static func success(_ result: some Encodable) -> Data {
        (try? encoder.encode(Success(result: result))) ?? failure("The reply could not be encoded.")
    }

    /// For a feature that reports itself as plain JSON values rather than an `Encodable`.
    static func success(json result: Any) -> Data {
        guard JSONSerialization.isValidJSONObject(["result": result]),
            let data = try? JSONSerialization.data(
                withJSONObject: ["ok": true, "result": result], options: [.sortedKeys])
        else { return failure("The reply could not be encoded.") }
        return data
    }

    static func failure(_ message: String) -> Data {
        (try? encoder.encode(Failure(error: message))) ?? Data("{\"ok\":false}".utf8)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
