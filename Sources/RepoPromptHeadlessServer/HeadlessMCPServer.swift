import Foundation
import Logging
import MCP
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct HeadlessMCPServer {
    static let version = "0.1.0"

    let host: HeadlessWorkspaceHost

    func run() async throws {
        var logger = Logger(label: "rpce-headless")
        logger.logLevel = .warning
        let transport = StdioTransport(logger: logger)
        try await serve(transport: transport, discoveryRestricted: false)
    }

    func runSocketConnection(fd: Int32) async throws {
        var logger = Logger(label: "rpce-headless.socket")
        logger.logLevel = .warning
        let descriptor = FileDescriptor(rawValue: fd)
        let transport = StdioTransport(input: descriptor, output: descriptor, logger: logger)
        defer { closeDescriptor(fd) }
        try await serve(transport: transport, discoveryRestricted: true)
    }

    func runFullAccessSocketConnection(fd: Int32, expectedToken: String) async throws {
        var logger = Logger(label: "rpce-headless.socket")
        logger.logLevel = .warning
        defer { closeDescriptor(fd) }

        let authLine = try await readSocketAuthLine(fd: fd)
        guard case let .line(lineBytes) = authLine else {
            if case .timeout = authLine { return }
            try? writeSocketAuthStatus(fd: fd, status: "rejected")
            return
        }

        guard let token = decodeSocketAuthToken(lineBytes),
              constantTimeEquals(token, expectedToken)
        else {
            try? writeSocketAuthStatus(fd: fd, status: "rejected")
            return
        }

        let descriptor = FileDescriptor(rawValue: fd)
        let transport = StdioTransport(input: descriptor, output: descriptor, logger: logger)
        try writeSocketAuthStatus(fd: fd, status: "accepted")
        try await serve(transport: transport, discoveryRestricted: false)
    }

    private func serve(transport: some Transport, discoveryRestricted: Bool) async throws {
        var logger = Logger(label: "rpce-headless")
        logger.logLevel = .warning
        let server = MCP.Server(
            name: "rpce-headless",
            version: Self.version,
            title: "RepoPrompt CE Headless",
            instructions: "Headless RepoPrompt CE context tools for one loaded workspace. Diagnostics are written to stderr; stdout is reserved for JSON-RPC.",
            capabilities: MCP.Server.Capabilities(tools: .init(listChanged: false)),
            configuration: MCP.Server.Configuration(responseSendTimeout: .seconds(120))
        )
        let tools = discoveryRestricted ? HeadlessToolSchemas.discoveryTools : HeadlessToolSchemas.tools
        let oracleService = OracleService(host: host)
        let contextBuilderService = HeadlessContextBuilderService(host: host)
        let agentSessionManager = discoveryRestricted ? nil : HeadlessAgentSessionManager(host: host)
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { params in
            let arguments = params.arguments ?? [:]
            do {
                if discoveryRestricted, !HeadlessToolSchemas.discoveryToolNames.contains(params.name) {
                    return CallTool.Result(
                        content: [.text(text: "Tool '\(params.name)' is unavailable on discovery-restricted socket connections. Allowed tools: \(HeadlessToolSchemas.discoveryToolNames.sorted().joined(separator: ", "))", annotations: nil, _meta: nil)],
                        isError: true
                    )
                }
                return try await callTool(name: params.name, arguments: arguments, host: host, oracleService: oracleService, contextBuilderService: contextBuilderService, agentSessionManager: agentSessionManager)
            } catch let failure as HeadlessToolFailure {
                return CallTool.Result(
                    content: [.text(text: failure.message, annotations: nil, _meta: nil)],
                    isError: true
                )
            } catch let mcpError as MCPError {
                throw mcpError
            } catch {
                return CallTool.Result(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }
        do {
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        } catch {
            await agentSessionManager?.shutdown()
            await oracleService.shutdown()
            throw error
        }
        await agentSessionManager?.shutdown()
        await oracleService.shutdown()
    }

    private func callTool(
        name: String,
        arguments: [String: MCP.Value],
        host: HeadlessWorkspaceHost,
        oracleService: OracleService,
        contextBuilderService: HeadlessContextBuilderService,
        agentSessionManager: HeadlessAgentSessionManager?
    ) async throws -> CallTool.Result {
        switch name {
        case "read_file":
            guard let path = arguments["path"]?.stringValue else { throw HeadlessToolFailure(message: "missing path") }
            let text = try await host.readFile(
                path: path,
                startLine: arguments["start_line"]?.intCoerced() ?? arguments["offset"]?.intCoerced(),
                limit: arguments["limit"]?.intCoerced()
            )
            return textResult(text)
        case "get_file_tree":
            let text = try await host.fileTree(
                type: arguments["type"]?.stringValue ?? "files",
                mode: arguments["mode"]?.stringValue ?? "auto",
                path: arguments["path"]?.stringValue,
                maxDepth: arguments["max_depth"]?.intCoerced()
            )
            return textResult(text)
        case "file_search":
            return try await textResult(host.fileSearch(args: arguments))
        case "get_code_structure":
            let text = try await host.codeStructure(
                paths: arguments["paths"]?.stringArray,
                scope: arguments["scope"]?.stringValue?.lowercased() ?? "paths",
                maxResults: arguments["max_results"]?.intCoerced() ?? 10
            )
            return textResult(text)
        case "manage_selection":
            let reply = try await host.manageSelection(args: arguments)
            return try jsonTextResult(reply)
        case "workspace_context":
            let reply = try await host.workspaceContext(args: arguments)
            return try CallTool.Result(
                content: [.text(text: reply.context.isEmpty ? HeadlessJSON.string(reply) : reply.context, annotations: nil, _meta: nil)],
                structuredContent: reply,
                isError: false
            )
        case "prompt":
            let op = arguments["op"]?.stringValue?.lowercased() ?? "get"
            return try await textResult(host.prompt(op: op, text: arguments["text"]?.stringValue))
        case "oracle_send":
            return try await OracleSendTool.call(arguments: arguments, service: oracleService)
        case "context_builder":
            let request = try HeadlessContextBuilderService.requestFromMCP(arguments: arguments)
            let execution = try await contextBuilderService.run(request: request, oracleService: oracleService)
            return try jsonTextResult(execution.mcpResult)
        case "agent_run":
            guard let agentSessionManager else {
                throw HeadlessToolFailure(message: "agent_run is unavailable on discovery-restricted socket connections.")
            }
            return try await agentSessionManager.executeAgentRun(arguments: arguments)
        case "agent_manage":
            guard let agentSessionManager else {
                throw HeadlessToolFailure(message: "agent_manage is unavailable on discovery-restricted socket connections.")
            }
            return try await agentSessionManager.executeAgentManage(arguments: arguments)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(name)")
        }
    }

    private func textResult(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private func jsonTextResult(_ value: some Codable) throws -> CallTool.Result {
        try CallTool.Result(
            content: [.text(text: HeadlessJSON.string(value), annotations: nil, _meta: nil)],
            structuredContent: value,
            isError: false
        )
    }

    private enum SocketAuthLine {
        case line([UInt8])
        case malformed
        case oversized
        case timeout
    }

    private struct SocketAuthRequest: Decodable {
        let rpceAuth: SocketAuthToken

        enum CodingKeys: String, CodingKey {
            case rpceAuth = "rpce_auth"
        }
    }

    private struct SocketAuthToken: Decodable {
        let token: String
    }

    private func readSocketAuthLine(fd: Int32) async throws -> SocketAuthLine {
        let maxBytes = 4096
        let timeout = Date().addingTimeInterval(10)
        let originalFlags = fcntl(fd, F_GETFL)
        guard originalFlags >= 0 else { throw POSIXFailure(operation: "fcntl(F_GETFL)", code: errno) }
        guard fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            throw POSIXFailure(operation: "fcntl(F_SETFL)", code: errno)
        }
        defer { _ = fcntl(fd, F_SETFL, originalFlags) }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(128)

        while Date() < timeout {
            var byte: UInt8 = 0
            let result = withUnsafeMutablePointer(to: &byte) { pointer in
                read(fd, pointer, 1)
            }
            if result == 1 {
                if byte == 0x0A {
                    return .line(bytes)
                }
                guard bytes.count < maxBytes else { return .oversized }
                bytes.append(byte)
                continue
            }
            if result == 0 {
                return .malformed
            }

            let code = errno
            if code == EINTR { continue }
            if code == EAGAIN || code == EWOULDBLOCK {
                try await Task.sleep(for: .milliseconds(10))
                continue
            }
            throw POSIXFailure(operation: "read", code: code)
        }

        return .timeout
    }

    private func decodeSocketAuthToken(_ bytes: [UInt8]) -> String? {
        guard let request = try? JSONDecoder().decode(SocketAuthRequest.self, from: Data(bytes)) else {
            return nil
        }
        return request.rpceAuth.token
    }

    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8)
        let rhs = Array(b.utf8)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        var diff = lhs.count ^ rhs.count
        for index in 0 ..< max(lhs.count, rhs.count) {
            diff |= Int(lhs[index % lhs.count] ^ rhs[index % rhs.count])
        }
        return diff == 0
    }

    private func writeSocketAuthStatus(fd: Int32, status: String) throws {
        let bytes = Array("{\"rpce_auth\":{\"status\":\"\(status)\"}}\n".utf8)
        var offset = 0
        while offset < bytes.count {
            let result = bytes.withUnsafeBytes { buffer in
                write(fd, buffer.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            if result > 0 {
                offset += result
                continue
            }
            if result == 0 { throw POSIXFailure(operation: "write", code: EPIPE) }
            let code = errno
            if code == EINTR { continue }
            throw POSIXFailure(operation: "write", code: code)
        }
    }

    private func closeDescriptor(_ fd: Int32) {
        #if canImport(Darwin)
            Darwin.close(fd)
        #elseif canImport(Glibc)
            Glibc.close(fd)
        #endif
    }
}
