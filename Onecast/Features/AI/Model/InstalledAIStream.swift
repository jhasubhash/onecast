import Foundation

struct InstalledAIStreamFrame: Equatable, Sendable {
    var events: [AIStreamEvent] = []
    var sessionID: String?
    var error: String?
    var completed = false
}

enum InstalledAIStreamDecoder {
    static func decode(_ data: Data, kind: InstalledAIKind) -> InstalledAIStreamFrame {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else { return InstalledAIStreamFrame() }
        switch kind {
        case .openCode: return openCode(object, type: type)
        case .claude: return claude(object, type: type)
        case .codex: return InstalledAIStreamFrame()
        case .copilot: return copilot(object, type: type)
        }
    }

    private static func openCode(
        _ object: [String: Any], type: String
    ) -> InstalledAIStreamFrame {
        var frame = InstalledAIStreamFrame(sessionID: object["sessionID"] as? String)
        let part = object["part"] as? [String: Any]
        switch type {
        case "text":
            if let text = part?["text"] as? String, !text.isEmpty { frame.events = [.text(text)] }
        case "step_start":
            frame.events = [.thinking]
        case "step_finish":
            if let tokens = part?["tokens"] as? [String: Any] {
                frame.events.append(
                    .usage(
                        AIUsage(
                            inputTokens: integer(tokens["input"]),
                            outputTokens: integer(tokens["output"]))))
            }
            frame.completed = true
        case "error":
            frame.error = message(in: object) ?? "OpenCode could not finish the response."
        default:
            break
        }
        return frame
    }

    /// Copilot's `--output-format json` is JSONL: incremental text arrives as `assistant.message_delta`
    /// (`data.deltaContent`), and a top-level `result` line ends the turn.
    private static func copilot(
        _ object: [String: Any], type: String
    ) -> InstalledAIStreamFrame {
        var frame = InstalledAIStreamFrame()
        switch type {
        case "assistant.message_delta":
            if let data = object["data"] as? [String: Any],
                let delta = data["deltaContent"] as? String, !delta.isEmpty
            {
                frame.events = [.text(delta)]
            }
        case "result":
            frame.sessionID = object["sessionId"] as? String
            if let code = integer(object["exitCode"]), code != 0 {
                frame.error = "Copilot exited with an error."
            }
            frame.completed = true
        default:
            break
        }
        return frame
    }

    private static func claude(
        _ object: [String: Any], type: String
    ) -> InstalledAIStreamFrame {
        var frame = InstalledAIStreamFrame()
        // Summaries arrive as several thinking blocks; a break keeps them from running together.
        if type == "stream_event", let event = object["event"] as? [String: Any],
            event["type"] as? String == "content_block_start",
            (event["content_block"] as? [String: Any])?["type"] as? String == "thinking"
        {
            frame.events = [.thinking, .reasoning("\n\n")]
            return frame
        }
        if type == "stream_event", let event = object["event"] as? [String: Any],
            let delta = event["delta"] as? [String: Any]
        {
            switch delta["type"] as? String {
            case "text_delta":
                if let text = delta["text"] as? String, !text.isEmpty {
                    frame.events = [.text(text)]
                }
            case "thinking_delta":
                let thinking = delta["thinking"] as? String ?? ""
                frame.events = thinking.isEmpty ? [.thinking] : [.thinking, .reasoning(thinking)]
            default:
                break
            }
            return frame
        }
        guard type == "result" else { return frame }
        if object["is_error"] as? Bool == true {
            frame.error = object["result"] as? String ?? "Claude could not finish the response."
            return frame
        }
        if let usage = object["usage"] as? [String: Any] {
            frame.events.append(.usage(claudeUsage(usage, result: object)))
        }
        frame.completed = true
        return frame
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// Cached prompt tokens sit outside `input_tokens`, and only `modelUsage` names the window.
    private static func claudeUsage(_ usage: [String: Any], result: [String: Any]) -> AIUsage {
        let cached = [usage["cache_read_input_tokens"], usage["cache_creation_input_tokens"]]
            .compactMap(integer)
        let details = usage["output_tokens_details"] as? [String: Any]
        // A side model (Haiku) may share the turn; the conversation's read the largest prompt.
        let model = (result["modelUsage"] as? [String: Any])?.values
            .compactMap { $0 as? [String: Any] }
            .max { rank($0) < rank($1) }
        return AIUsage(
            inputTokens: integer(usage["input_tokens"]),
            outputTokens: integer(usage["output_tokens"]),
            cachedInputTokens: cached.isEmpty ? nil : cached.reduce(0, +),
            reasoningTokens: integer(details?["thinking_tokens"]),
            contextWindow: integer(model?["contextWindow"]),
            costUSD: (result["total_cost_usd"] as? NSNumber)?.doubleValue)
    }

    private static func rank(_ model: [String: Any]) -> (prompt: Int, window: Int) {
        let prompt = ["inputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"]
            .compactMap { integer(model[$0]) }.reduce(0, +)
        return (prompt, integer(model["contextWindow"]) ?? 0)
    }

    private static func message(in object: [String: Any]) -> String? {
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return nil
    }
}
