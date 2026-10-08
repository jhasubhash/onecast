import Foundation

/// The agent channel's pure layer: framing, decoding, keys, conditions and tree pruning.
@main
struct AgentControlTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func request(_ text: String) -> AgentHTTPRequest.Parse {
        AgentHTTPRequest.parse(Data(text.utf8))
    }

    static func decode(_ json: String) -> Result<AgentRequest, Error> {
        Result { try AgentRequest.decode(Data(json.utf8)) }
    }

    static func main() {
        framing()
        commands()
        keys()
        conditions()
        pruning()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func framing() {
        let body = #"{"action":"ping"}"#
        let full =
            "POST / HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer abc\r\n"
            + "Content-Length: \(body.utf8.count)\r\n\r\n" + body
        guard case .request(let parsed) = request(full) else {
            return expect(false, "a whole request parses")
        }
        expect(parsed.method == "POST" && parsed.path == "/", "method and path are read")
        expect(parsed.bearerToken == "abc", "the bearer token is read")
        expect(String(decoding: parsed.body, as: UTF8.self) == body, "the body is exactly Content-Length")
        expect(request(String(full.dropLast(3))) == .incomplete, "a short body waits for more")
        expect(request("POST / HTTP/1.1\r\nHost: x\r\n") == .incomplete, "a header without its end waits")
        if case .malformed = request("garbage\r\n\r\n") {
            passes += 1
        } else {
            expect(false, "a bad request line is malformed, not incomplete")
        }
        let lower = "POST / HTTP/1.1\r\nauthorization: bearer  t0k \r\n\r\n"
        if case .request(let headers) = request(lower) {
            expect(headers.bearerToken == "t0k", "header names and the scheme are case-insensitive")
        }
        let reply = AgentHTTPRequest.response(status: 401, body: Data("{}".utf8))
        let response = String(decoding: reply, as: UTF8.self)
        expect(response.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"), "a reply names its status")
        expect(response.hasSuffix("Content-Length: 2\r\nConnection: close\r\n\r\n{}"), "a reply closes")
    }

    static func commands() {
        expect((try? decode(#"{"action":"ping"}"#).get().command) == .ping, "ping decodes")
        expect(
            (try? decode(#"{"action":"state"}"#).get().command)
                == .state(includeContent: false, includeElements: true, pruned: true),
            "state defaults hide content and prune")
        expect(
            (try? decode(#"{"action":"key","keys":["cmd+k","down"],"count":2}"#).get().command)
                == .key(["cmd+k", "down"], count: 2, window: nil),
            "a key list and a count decode")
        expect(
            (try? decode(#"{"action":"key","key":"return"}"#).get().command)
                == .key(["return"], count: 1, window: nil),
            "a single key is a one-item list")
        if case .failure = decode(#"{"action":"key","key":"down","count":0}"#) {
            passes += 1
        } else {
            expect(false, "a zero count is refused")
        }
        if case .failure = decode(#"{"action":"select","index":true}"#) {
            passes += 1
        } else {
            expect(false, "a JSON boolean is not an index")
        }
        if case .failure = decode(#"{"action":"state","includeContent":1}"#) {
            passes += 1
        } else {
            expect(false, "a JSON 1 is not true")
        }
        if case .failure(let error) = decode(#"{"action":"launchRockets"}"#) {
            expect(
                (error as? AgentCommand.DecodeError) == .unknownAction("launchRockets"),
                "an unknown action is named")
        }
        let shown = try? decode(
            #"{"action":"show","mode":"emoji","until":{"visible":true},"timeout":2}"#
        ).get()
        expect(shown?.command == .show(mode: "emoji", query: nil), "show decodes its mode")
        expect(shown?.until == AgentCondition(visible: true), "until nests under an action")
        expect(shown?.timeout == 2, "a timeout is carried")
        let waited = try? decode(#"{"action":"waitFor","mode":"ai","minimumRows":3}"#).get()
        expect(waited?.until == AgentCondition(mode: "ai", minimumRows: 3), "waitFor's condition is flat")
        if case .failure = decode(#"{"action":"waitFor"}"#) {
            passes += 1
        } else {
            expect(false, "waitFor without a condition is refused")
        }
        if case .failure = decode(#"{"action":"hide","timeout":600}"#) {
            passes += 1
        } else {
            expect(false, "a timeout past the cap is refused")
        }
    }

    static func keys() {
        let down = try? AgentKey.parse("down")
        expect(down?.keyCode == 125 && down?.modifiers == [.function, .numericPad], "an arrow implies fn")
        let palette = try? AgentKey.parse("cmd+K")
        expect(palette?.keyCode == 40 && palette?.modifiers == [.command, .shift], "⌘⇧K from a capital")
        expect((try? AgentKey.parse("⌘,"))?.keyCode == 43, "a symbol modifier and punctuation parse")
        expect((try? AgentKey.parse("ctrl+opt+return"))?.modifiers == [.control, .option], "names stack")
        expect((try? AgentKey.parse("cmd++"))?.charactersIgnoringModifiers == "=", "cmd++ is plus")
        expect((try? AgentKey.parse("+"))?.modifiers == .shift, "a bare plus is ⇧=")
        expect((try? AgentKey.parse("hyper+k")) == nil, "an unknown modifier is refused")
        expect((try? AgentKey.parse("blorp")) == nil, "an unknown key name is refused")
        expect(AgentKey.typing("?")?.keyCode == 44, "a shifted symbol types from its base key")
        expect(AgentKey.typing("é")?.keyCode == 0, "a character off the layout still types")
        expect(AgentKey.typing("\n")?.keyCode == 36, "a newline is Return")
    }

    static func snapshot(
        visible: Bool = true, mode: String = "launcher", rows: Int? = nil,
        windows: [AgentSnapshot.Window] = []
    ) -> AgentSnapshot {
        let frame = AgentSnapshot.Rect(x: 0, y: 0, width: 1, height: 1)
        return AgentSnapshot(
            build: .init(bundleID: "b", version: "1", pid: 1, accessibilityTrusted: true),
            palette: .init(
                visible: visible, mode: mode, query: "q", selection: 0, backStack: [], aiBar: false,
                collapsed: false, editingField: false, controlListOpen: false, frame: nil,
                rows: rows.map { count in
                    (0..<count).map {
                        .init(index: $0, label: "row \($0)", identifier: nil, selected: $0 == 0, frame: frame)
                    }
                }),
            windows: windows, focus: .init(keyWindow: nil, firstResponder: nil, frontmostApp: nil))
    }

    static func window(_ id: String, texts: [String]) -> AgentSnapshot.Window {
        var window = AgentSnapshot.Window(
            id: id, title: id, className: "NSPanel", level: 0, isKey: false, isVisible: true,
            frame: .init(x: 0, y: 0, width: 1, height: 1))
        window.elements = texts.map { AgentElement(role: "AXStaticText", value: $0) }
        return window
    }

    static func conditions() {
        expect(AgentCondition(visible: true, mode: "launcher").isMet(by: snapshot()), "facts that hold")
        expect(!AgentCondition(mode: "ai").isMet(by: snapshot()), "a different mode does not")
        expect(!AgentCondition(minimumRows: 1).isMet(by: snapshot()), "no rows reported is zero rows")
        expect(AgentCondition(minimumRows: 3).isMet(by: snapshot(rows: 3)), "enough rows")
        let panes = [window("palette", texts: ["Calculator"]), window("hud", texts: ["Copied"])]
        expect(AgentCondition(text: "calc").isMet(by: snapshot(windows: panes)), "text matches any window")
        expect(
            !AgentCondition(text: "Copied", window: "palette").isMet(by: snapshot(windows: panes)),
            "text scoped to a window looks only there")
        expect(AgentCondition(absentWindow: "dialog").isMet(by: snapshot(windows: panes)), "an absent window")
        expect(!AgentCondition(absentText: "copied").isMet(by: snapshot(windows: panes)), "a present text")
        expect(AgentCondition(text: "x").needsElements, "a text check needs elements")
        expect(!AgentCondition(mode: "x").needsElements, "a palette check does not")
        expect(
            AgentCondition(mode: "ai", minimumRows: 2).summary == "mode=ai, rows>=2",
            "a summary names each wish")
    }

    static func pruning() {
        let tree = [
            AgentElement(
                role: "AXGroup",
                children: [
                    AgentElement(
                        role: "AXGroup", children: [AgentElement(role: "AXStaticText", value: "Hi")]),
                    AgentElement(role: "AXImage"),
                    AgentElement(role: "AXButton"),
                ])
        ]
        let pruned = AgentElement.pruned(tree)
        expect(pruned.map(\.role) == ["AXStaticText", "AXButton"], "anonymous groups lift, empty leaves drop")
        let labelled = [
            AgentElement(role: "AXGroup", label: "Row", children: [AgentElement(role: "AXImage")])
        ]
        expect(AgentElement.pruned(labelled).first?.children == nil, "an informative node keeps its place")
        expect(tree[0].contains(text: "hi"), "contains searches the subtree, ignoring case")
    }
}
