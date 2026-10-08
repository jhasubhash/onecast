import Foundation

/// One command, and optionally what must hold before the reply is sent.
struct AgentRequest: Equatable, Sendable {
    static let defaultTimeout: Double = 5
    static let maximumTimeout: Double = 60

    let command: AgentCommand
    let until: AgentCondition?
    let timeout: Double

    static func decode(_ data: Data) throws -> AgentRequest {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let fields = object as? [String: Any]
        else { throw AgentCommand.DecodeError.invalid("The body must be a JSON object.") }
        let arguments = AgentCommand.Arguments(fields: fields)
        let command = try AgentCommand.decode(arguments)
        let timeout: Double = try arguments.optional("timeout") ?? defaultTimeout
        guard timeout > 0, timeout <= maximumTimeout else {
            throw AgentCommand.DecodeError.invalid("\"timeout\" must be above 0 and at most 60.")
        }
        // `waitFor` takes its condition flat; any other action nests it under `until`.
        let conditionFields: [String: Any]? =
            command == .waitFor ? fields : try arguments.optional("until")
        let until = try conditionFields.map { try AgentCondition(AgentCommand.Arguments(fields: $0)) }
        if command == .waitFor, until?.isEmpty ?? true {
            throw AgentCommand.DecodeError.invalid("waitFor needs at least one condition.")
        }
        return AgentRequest(
            command: command, until: until?.isEmpty == true ? nil : until, timeout: timeout)
    }
}
