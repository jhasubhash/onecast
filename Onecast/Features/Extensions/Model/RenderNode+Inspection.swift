import Foundation

extension RenderNode {
    /// The tree as plain JSON, hoisted slot nodes included, for a reader outside the renderer.
    var inspection: [String: Any] {
        var object: [String: Any] = ["type": type, "id": id]
        if let text { object["text"] = text }
        if !props.isEmpty { object["props"] = props.mapValues(\.inspection) }
        if !children.isEmpty { object["children"] = children.map(\.inspection) }
        return object
    }
}

extension RenderValue {
    var inspection: Any {
        switch self {
        case .node(let node): node.inspection
        case .array(let values): values.map(\.inspection)
        case .object(let values): values.mapValues(\.inspection)
        default: jsonValue
        }
    }
}
