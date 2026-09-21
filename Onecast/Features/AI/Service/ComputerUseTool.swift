import CoreGraphics
import Foundation

/// Native computer tools for in-app chat — screenshot, move, click, type, scroll, drag; vision-gated.
struct ComputerUseTool {
    let controller: ComputerController

    static let screenshotName = "computer__screenshot"
    static let clickName = "computer__click"
    static let moveName = "computer__move"
    static let typeName = "computer__type"
    static let keyName = "computer__key"
    static let scrollName = "computer__scroll"
    static let dragName = "computer__drag"

    static let tools: [AITool] = [
        screenshotTool, clickTool, moveTool, typeTool, keyTool, scrollTool, dragTool,
    ]

    /// Appended to the pointer tools so the fallback preference survives even with system prompts off.
    static let fallbackNote =
        " This drives the user's real cursor and keyboard. First prefer a direct route to the app "
        + "when one is available to you - an AppleScript command to the app itself, its own "
        + "command-line tool, or an MCP tool - and otherwise use these tools to carry out the task "
        + "directly; never claim you cannot control the Mac when these tools are offered."

    static func handles(_ name: String) -> Bool {
        name.hasPrefix("computer__")
    }

    func invoke(_ call: AIToolCall) async -> AIToolResult {
        do {
            switch call.name {
            case Self.screenshotName:
                // No swallowing: a denied capture must surface so the model never acts blind.
                let shot = try await controller.screenshot()
                return result(call.id, "Screenshot taken.", shot)
            case Self.clickName:
                let a = try decode(ClickArguments.self, call)
                try await controller.click(
                    at: CGPoint(x: a.x, y: a.y),
                    button: a.button == "right" ? .right : .left,
                    count: a.double == true ? 2 : 1)
                return await afterAction(
                    call.id, "Clicked \(a.button ?? "left") at (\(a.x), \(a.y)).")
            case Self.moveName:
                let a = try decode(PointArguments.self, call)
                try await controller.move(to: CGPoint(x: a.x, y: a.y))
                return await afterAction(call.id, "Moved to (\(a.x), \(a.y)).")
            case Self.typeName:
                let a = try decode(TypeArguments.self, call)
                try await controller.type(a.text)
                return await afterAction(call.id, "Typed \(a.text.count) characters.")
            case Self.keyName:
                let a = try decode(KeyArguments.self, call)
                try await controller.key(a.keys)
                return await afterAction(call.id, "Pressed \(a.keys).")
            case Self.scrollName:
                let a = try decode(ScrollArguments.self, call)
                try await controller.scroll(at: CGPoint(x: a.x, y: a.y), dx: a.dx, dy: a.dy)
                return await afterAction(call.id, "Scrolled at (\(a.x), \(a.y)).")
            case Self.dragName:
                let a = try decode(DragArguments.self, call)
                try await controller.drag(
                    from: CGPoint(x: a.fromX, y: a.fromY), to: CGPoint(x: a.toX, y: a.toY))
                return await afterAction(
                    call.id, "Dragged from (\(a.fromX), \(a.fromY)) to (\(a.toX), \(a.toY)).")
            default:
                return .failure(call.id, "Unknown computer tool \"\(call.name)\".")
            }
        } catch let error as ComputerUseError {
            return .failure(call.id, error.errorDescription ?? "Computer action failed.")
        } catch {
            return .failure(call.id, "Bad arguments for \(call.name): \(error.localizedDescription)")
        }
    }

    /// Re-screenshots after the action so the model sees its effect; a failed capture surfaces as error.
    private func afterAction(_ callID: String, _ note: String) async -> AIToolResult {
        do {
            return result(callID, note, try await controller.screenshot())
        } catch let error as ComputerUseError {
            return .failure(
                callID,
                "\(note) But the follow-up screenshot failed: "
                    + (error.errorDescription ?? "unknown error")
                    + " Take a screenshot before the next action.")
        } catch {
            return .failure(
                callID,
                "\(note) But the follow-up screenshot failed. Take a screenshot before the next "
                    + "action.")
        }
    }

    private func result(_ callID: String, _ note: String, _ shot: ComputerController.Shot)
        -> AIToolResult
    {
        AIToolResult(
            callID: callID,
            content:
                "\(note) The main display is \(shot.width)×\(shot.height) points; click and move "
                + "coordinates are in this space, origin top-left.",
            isError: false, images: [shot.image])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ call: AIToolCall) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(call.arguments.utf8))
    }

    private struct PointArguments: Decodable { let x: Int; let y: Int }
    private struct ClickArguments: Decodable {
        let x: Int
        let y: Int
        let button: String?
        let double: Bool?
    }
    private struct TypeArguments: Decodable { let text: String }
    private struct KeyArguments: Decodable { let keys: String }
    private struct ScrollArguments: Decodable {
        let x: Int
        let y: Int
        let dx: Int
        let dy: Int
    }
    private struct DragArguments: Decodable {
        let fromX: Int
        let fromY: Int
        let toX: Int
        let toY: Int

        enum CodingKeys: String, CodingKey {
            case fromX = "from_x"
            case fromY = "from_y"
            case toX = "to_x"
            case toY = "to_y"
        }
    }

    private static let origin = "Computer"

    private static let screenshotTool = AITool(
        name: screenshotName,
        description:
            "Capture a screenshot of the main display so you can see the screen. First prefer a direct "
            + "route to the app when one is available to you — an AppleScript command to the app itself, "
            + "its own command-line tool, or an MCP tool — and otherwise drive the screen and pointer "
            + "directly; never claim you cannot control the Mac. Screenshot before you act this way and "
            + "again after each action to check its effect.",
        parameters: .object(["type": .string("object"), "properties": .object([:])]),
        origin: origin, title: "Take a screenshot")

    private static let clickTool = AITool(
        name: clickName,
        description:
            "Click the mouse at a screen coordinate, in the point space of the latest screenshot "
            + "(origin top-left). Set double to true for a double-click, button to \"right\" for a "
            + "right-click." + Self.fallbackNote,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "x": .object(["type": .string("integer")]),
                "y": .object(["type": .string("integer")]),
                "button": .object([
                    "type": .string("string"),
                    "enum": .array([.string("left"), .string("right")]),
                ]),
                "double": .object(["type": .string("boolean")]),
            ]),
            "required": .array([.string("x"), .string("y")]),
        ]),
        origin: origin, title: "Click")

    private static let moveTool = AITool(
        name: moveName,
        description:
            "Move the mouse pointer to a screen coordinate without clicking." + Self.fallbackNote,
        parameters: pointSchema,
        origin: origin, title: "Move the pointer")

    private static let typeTool = AITool(
        name: typeName,
        description:
            "Type text at the current focus, as if from the keyboard. Click the field you want first."
            + Self.fallbackNote,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object(["type": .string("string")])
            ]),
            "required": .array([.string("text")]),
        ]),
        origin: origin, title: "Type text")

    private static let keyTool = AITool(
        name: keyName,
        description:
            "Press a key or chord, e.g. \"return\", \"tab\", \"escape\", \"left\", or \"cmd+a\", "
            + "\"cmd+shift+4\". Modifiers: cmd, shift, opt, ctrl, fn, joined with +."
            + Self.fallbackNote,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "keys": .object(["type": .string("string")])
            ]),
            "required": .array([.string("keys")]),
        ]),
        origin: origin, title: "Press a key")

    private static let scrollTool = AITool(
        name: scrollName,
        description:
            "Scroll at a screen coordinate by a pixel delta. Positive dy scrolls the content up "
            + "(wheel away from you), negative scrolls down; dx scrolls horizontally."
            + Self.fallbackNote,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "x": .object(["type": .string("integer")]),
                "y": .object(["type": .string("integer")]),
                "dx": .object(["type": .string("integer")]),
                "dy": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("x"), .string("y"), .string("dx"), .string("dy")]),
        ]),
        origin: origin, title: "Scroll")

    private static let dragTool = AITool(
        name: dragName,
        description:
            "Press at one coordinate and release at another, dragging in between — for selecting text, "
            + "moving a window, or a slider." + Self.fallbackNote,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "from_x": .object(["type": .string("integer")]),
                "from_y": .object(["type": .string("integer")]),
                "to_x": .object(["type": .string("integer")]),
                "to_y": .object(["type": .string("integer")]),
            ]),
            "required": .array([
                .string("from_x"), .string("from_y"), .string("to_x"), .string("to_y"),
            ]),
        ]),
        origin: origin, title: "Drag")

    private static let pointSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "x": .object(["type": .string("integer")]),
            "y": .object(["type": .string("integer")]),
        ]),
        "required": .array([.string("x"), .string("y")]),
    ])
}
