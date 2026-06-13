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

    private func serve<T: Transport>(transport: T, discoveryRestricted: Bool) async throws {
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
            return textResult(try await host.fileSearch(args: arguments))
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
                content: [.text(text: reply.context.isEmpty ? try HeadlessJSON.string(reply) : reply.context, annotations: nil, _meta: nil)],
                structuredContent: reply,
                isError: false
            )
        case "prompt":
            let op = arguments["op"]?.stringValue?.lowercased() ?? "get"
            return textResult(try await host.prompt(op: op, text: arguments["text"]?.stringValue))
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

    private func jsonTextResult<T: Codable>(_ value: T) throws -> CallTool.Result {
        try CallTool.Result(
            content: [.text(text: HeadlessJSON.string(value), annotations: nil, _meta: nil)],
            structuredContent: value,
            isError: false
        )
    }

    private func closeDescriptor(_ fd: Int32) {
        #if canImport(Darwin)
            Darwin.close(fd)
        #elseif canImport(Glibc)
            Glibc.close(fd)
        #endif
    }
}
