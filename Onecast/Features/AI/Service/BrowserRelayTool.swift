import Foundation

/// Native tools that drive the user's own Chrome through omp's browser relay: list, open, read, run JS.
struct BrowserRelayTool: Sendable {
    let client = BrowserRelayClient()

    static let tabsName = "browser__tabs"
    static let openName = "browser__open"
    static let navigateName = "browser__navigate"
    static let evaluateName = "browser__evaluate"
    static let readName = "browser__read"
    static let screenshotName = "browser__screenshot"
    static let closeName = "browser__close"

    /// The screenshot only goes to a route that can look at it.
    static func tools(images: Bool) -> [AITool] {
        let text = [tabsTool, openTool, navigateTool, evaluateTool, readTool, closeTool]
        return images ? text + [screenshotTool] : text
    }

    static func handles(_ name: String) -> Bool {
        name.hasPrefix("browser__")
    }

    /// The CLI route's way in: the same tools, served by `AIToolBridge` through the helper.
    static func toolset() -> AIToolBridge.Toolset {
        let tool = BrowserRelayTool()
        return AIToolBridge.Toolset(
            slug: "onecast_browser", serverName: "onecast-browser-relay", namespace: "browser__",
            tools: tools(images: true), refusal: "The browser relay is not enabled in Onecast.",
            invoke: { await tool.invoke($0) })
    }

    private static let evaluateLimit = 60_000
    private static let readLimit = 20_000
    private static let loadWait: Duration = .seconds(15)

    func invoke(_ call: AIToolCall) async -> AIToolResult {
        do {
            switch call.name {
            case Self.tabsName:
                return .init(
                    callID: call.id, content: BrowserRelayPage.listing(try await client.pages()),
                    isError: false)
            case Self.openName:
                let a = try decode(OpenArguments.self, call)
                return try await open(call.id, a)
            case Self.navigateName:
                let a = try decode(NavigateArguments.self, call)
                let url = try webURL(a.url)
                try await client.withPage(a.tab) { cdp, session in
                    _ = try await cdp.send("Page.navigate", ["url": url.absoluteString], session: session)
                    try await Self.awaitLoad(cdp, session)
                }
                return .init(callID: call.id, content: "Tab \(a.tab) loaded \(url.absoluteString).", isError: false)
            case Self.evaluateName:
                let a = try decode(EvaluateArguments.self, call)
                let reply = try await client.withPage(a.tab) { cdp, session in
                    Self.Evaluation(
                        try await cdp.send(
                            "Runtime.evaluate",
                            ["expression": a.expression, "awaitPromise": true, "returnByValue": true],
                            session: session))
                }
                return .init(
                    callID: call.id, content: BrowserRelayPage.clipped(reply.text, to: Self.evaluateLimit),
                    isError: reply.threw)
            case Self.readName:
                let a = try decode(ReadArguments.self, call)
                let reply = try await client.withPage(a.tab) { cdp, session in
                    Self.Evaluation(
                        try await cdp.send(
                            "Runtime.evaluate",
                            [
                                "expression":
                                    "`${document.title}\\n${location.href}\\n\\n${document.body?.innerText ?? ''}`",
                                "returnByValue": true,
                            ], session: session))
                }
                return .init(
                    callID: call.id,
                    content: BrowserRelayPage.clipped(reply.text, to: a.maxChars ?? Self.readLimit),
                    isError: reply.threw)
            case Self.screenshotName:
                let a = try decode(TabArguments.self, call)
                let base64 = try await client.withPage(a.tab) { cdp, session in
                    try await cdp.send(
                        "Page.captureScreenshot", ["format": "jpeg", "quality": 70], session: session
                    )["data"] as? String
                }
                guard let base64, let data = Data(base64Encoded: base64) else {
                    return .failure(call.id, "The tab returned no screenshot.")
                }
                return AIToolResult(
                    callID: call.id, content: "Screenshot of tab \(a.tab).", isError: false,
                    images: [AIImage(data: data, mimeType: "image/jpeg")])
            case Self.closeName:
                let a = try decode(TabArguments.self, call)
                _ = try await client.withConnection { cdp in
                    try await cdp.send("Target.closeTarget", ["targetId": a.tab])["success"] as? Bool
                }
                return .init(callID: call.id, content: "Closed tab \(a.tab).", isError: false)
            default:
                return .failure(call.id, "Unknown browser tool \"\(call.name)\".")
            }
        } catch let error as BrowserRelayError {
            return .failure(call.id, error.errorDescription ?? "The browser call failed.")
        } catch {
            return .failure(call.id, "Bad arguments for \(call.name): \(error.localizedDescription)")
        }
    }

    /// Reuses a tab already on the URL's host, whose login it holds, unless a fresh one is asked for.
    private func open(_ callID: String, _ a: OpenArguments) async throws -> AIToolResult {
        let url = try webURL(a.url)
        if a.newTab != true, let page = BrowserRelayPage.reusable(for: url, in: try await client.pages()) {
            return .init(
                callID: callID,
                content:
                    "Reusing tab \(page.id) (\(page.title), \(page.url)), already on \(url.host() ?? ""); "
                    + "it was not navigated. Use browser__navigate to change its page.",
                isError: false)
        }
        let id = try await client.withConnection { cdp in
            try await cdp.send(
                "Target.createTarget", ["url": url.absoluteString, "background": true])["targetId"]
                as? String
        }
        guard let id else { return .failure(callID, "Chrome did not open a tab.") }
        try await client.withPage(id) { cdp, session in try await Self.awaitLoad(cdp, session) }
        return .init(callID: callID, content: "Opened tab \(id) at \(url.absoluteString).", isError: false)
    }

    /// Polls the document until it settles; a navigating page refuses evaluation, so misses retry.
    private static func awaitLoad(_ cdp: CDPConnection, _ session: String) async throws {
        let deadline = ContinuousClock.now + loadWait
        while ContinuousClock.now < deadline {
            let state = try? await cdp.send(
                "Runtime.evaluate", ["expression": "document.readyState", "returnByValue": true],
                session: session, timeout: .seconds(3))
            if Evaluation(state ?? [:]).text == "complete" { return }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func webURL(_ text: String) throws -> URL {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme), url.host() != nil
        else { throw BrowserRelayError.protocolError("\(text) is not an http(s) URL.") }
        return url
    }

    private func decode<T: Decodable>(_ type: T.Type, _ call: AIToolCall) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(call.arguments.utf8))
    }

    /// `Runtime.evaluate`'s reply as text: the value as JSON (a string bare), or what it threw.
    private struct Evaluation: Sendable {
        let text: String
        let threw: Bool

        init(_ reply: [String: Any]) {
            if let exception = reply["exceptionDetails"] as? [String: Any] {
                let thrown = exception["exception"] as? [String: Any]
                text =
                    thrown?["description"] as? String ?? exception["text"] as? String
                    ?? "The expression threw."
                threw = true
                return
            }
            threw = false
            let result = reply["result"] as? [String: Any] ?? [:]
            if let string = result["value"] as? String {
                text = string
            } else if let value = result["value"],
                let data = try? JSONSerialization.data(
                    withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]),
                let json = String(bytes: data, encoding: .utf8)
            {
                text = json
            } else {
                text = result["description"] as? String ?? result["type"] as? String ?? "undefined"
            }
        }
    }

    private struct TabArguments: Decodable { let tab: String }
    private struct OpenArguments: Decodable {
        let url: String
        let newTab: Bool?

        enum CodingKeys: String, CodingKey {
            case url
            case newTab = "new_tab"
        }
    }
    private struct NavigateArguments: Decodable {
        let tab: String
        let url: String
    }
    private struct EvaluateArguments: Decodable {
        let tab: String
        let expression: String
    }
    private struct ReadArguments: Decodable {
        let tab: String
        let maxChars: Int?

        enum CodingKeys: String, CodingKey {
            case tab
            case maxChars = "max_chars"
        }
    }

    private static let origin = "Browser"
    private static let reach =
        " This is the user's own Chrome, reached through the omp browser relay, so it carries their "
        + "logins (SSO included)."

    private static let tabSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object(["tab": .object(["type": .string("string")])]),
        "required": .array([.string("tab")]),
    ])

    private static let tabsTool = AITool(
        name: tabsName,
        description:
            "List the tabs open in the user's Chrome: id, title and URL. Pass an id as `tab` to the "
            + "other browser tools." + reach,
        parameters: .object(["type": .string("object"), "properties": .object([:])]),
        origin: origin, title: "List tabs")

    private static let openTool = AITool(
        name: openName,
        description:
            "Get a tab on a URL and return its id. A tab already on that host is reused as it is, so a "
            + "logged-in page stays logged in; set new_tab to true to open a fresh background tab "
            + "instead." + reach,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "url": .object(["type": .string("string")]),
                "new_tab": .object(["type": .string("boolean")]),
            ]),
            "required": .array([.string("url")]),
        ]),
        origin: origin, title: "Open a tab")

    private static let navigateTool = AITool(
        name: navigateName,
        description: "Load a URL in a tab and wait for the page to finish loading." + reach,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "tab": .object(["type": .string("string")]),
                "url": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("tab"), .string("url")]),
        ]),
        origin: origin, title: "Navigate")

    private static let evaluateTool = AITool(
        name: evaluateName,
        description:
            "Run a JavaScript expression in a tab's page and return its value as JSON. A returned "
            + "promise is awaited, and fetch() runs with the page's own cookies, so an in-page API call "
            + "is authenticated. One call must finish within about 15 seconds: start a long job in one "
            + "call, keep its state on `window`, and poll it in later calls." + reach,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "tab": .object(["type": .string("string")]),
                "expression": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("tab"), .string("expression")]),
        ]),
        origin: origin, title: "Run JavaScript")

    private static let readTool = AITool(
        name: readName,
        description:
            "Read a tab's title, URL and visible text, cut at max_chars (20000 by default)." + reach,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "tab": .object(["type": .string("string")]),
                "max_chars": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("tab")]),
        ]),
        origin: origin, title: "Read a page")

    private static let screenshotTool = AITool(
        name: screenshotName,
        description: "Capture a screenshot of a tab's visible page." + reach,
        parameters: tabSchema, origin: origin, title: "Screenshot a tab")

    private static let closeTool = AITool(
        name: closeName,
        description:
            "Close a tab. Only close tabs you opened with browser__open; never one the user had open.",
        parameters: tabSchema, origin: origin, title: "Close a tab")
}
