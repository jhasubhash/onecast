import Foundation

/// How a CLI route carries the latest message's pictures: inline for Claude, as files otherwise.
enum InstalledAIImageInput {
    /// Claude's `stream-json` input is one user message, its pictures ahead of the text.
    static func claudeUserLine(_ text: String, images: [AIImage]) -> Data? {
        let pictures: [[String: Any]] = images.map { image in
            [
                "type": "image",
                "source": [
                    "type": "base64", "media_type": image.mimeType,
                    "data": image.data.base64EncodedString()
                ]
            ]
        }
        let content: Any = images.isEmpty ? text : pictures + [["type": "text", "text": text]]
        var line = try? JSONSerialization.data(
            withJSONObject: ["type": "user", "message": ["role": "user", "content": content]])
        line?.append(0x0A)
        return line
    }

    /// The extension is how OpenCode and Copilot tell a picture's type from the file alone.
    static func fileName(for image: AIImage, index: Int) -> String {
        let fileExtension =
            switch image.mimeType {
            case "image/jpeg": "jpg"
            case "image/gif": "gif"
            case "image/webp": "webp"
            case "image/heic": "heic"
            default: "png"
            }
        return "image-\(index + 1).\(fileExtension)"
    }

    /// One flag per written picture; Claude takes them inline, so it never gets a file.
    static func arguments(for kind: InstalledAIKind, files: [URL]) -> [String] {
        let flag: String
        switch kind {
        case .openCode: flag = "--file"
        case .copilot: flag = "--attachment"
        case .claude, .codex: return []
        }
        return files.flatMap { [flag, $0.path] }
    }

    /// What the text says beside a message's pictures, since only the latest message's are re-sent.
    static func note(imageCount: Int, isLatest: Bool) -> String? {
        guard imageCount > 0 else { return nil }
        let noun = imageCount == 1 ? "image" : "images"
        return isLatest
            ? "[\(imageCount) \(noun) attached]"
            : "[\(imageCount) \(noun) shared earlier, not shown again]"
    }
}
