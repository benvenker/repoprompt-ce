import Foundation
import MCP

enum OracleSendTool {
    static func call(arguments: [String: MCP.Value], service: OracleService) async throws -> CallTool.Result {
        guard let message = arguments["message"]?.stringValue else { throw HeadlessToolFailure(message: "missing message") }
        let chatID = arguments["chat_id"]?.stringValue
        let includeContext = arguments["include_context"]?.boolCoerced() ?? (chatID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? false : true)
        let reply = try await service.send(
            message: message,
            chatID: chatID,
            model: arguments["model"]?.stringValue,
            includeContext: includeContext
        )
        var text = ""
        for try await delta in reply.stream {
            text += delta
        }
        return CallTool.Result(
            content: [.text(text: "chat_id: \(reply.chatID) | model: \(reply.model)\n\(text)", annotations: nil, _meta: nil)],
            isError: false
        )
    }
}
