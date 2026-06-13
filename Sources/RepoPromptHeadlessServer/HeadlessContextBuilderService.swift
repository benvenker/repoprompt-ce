import Foundation
import MCP

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct HeadlessContextBuilderRequest {
    let instructions: String
    let agentName: String
    let agentConfigPath: String?
    let socketPath: String?
    let tokenBudget: Int
    let responseType: ContextBuildResponseType
    let responseTypeName: String
    let timeoutSeconds: Int
    let exportResponse: Bool
}

struct HeadlessContextBuilderExecution {
    let contextID: String
    let request: HeadlessContextBuilderRequest
    let launch: RenderedAgentLaunch
    let socketPath: String
    let agentExit: Int32
    let harvest: HeadlessContextBuildHarvest
    let oracleReply: HeadlessContextBuilderOracleReply?
    let answer: String?

    var status: String {
        if agentExit != 0 { return "agent_failed" }
        if harvest.selectedFiles.isEmpty { return "empty_selection" }
        return "completed"
    }

    var mcpResult: HeadlessContextBuilderResult {
        let mode = oracleReply?.mode
        let followUpHint = oracleReply.map {
            "Continue this \(mode ?? "chat") conversation with oracle_send(chat_id: \"\($0.chatID)\", include_context: false)"
        }
        return HeadlessContextBuilderResult(
            contextID: contextID,
            status: status,
            prompt: harvest.prompt,
            fileCount: harvest.selectedFiles.count,
            totalTokens: harvest.totalTokens,
            tokenBudget: request.tokenBudget,
            promptMode: "headless",
            agent: request.agentName,
            agentExit: Int(agentExit),
            selection: harvest.selectedFiles.map { .init(path: $0.path, tokens: $0.tokens) },
            codemapFiles: harvest.codemapFiles,
            responseType: request.responseTypeName,
            plan: request.responseType == .review ? nil : answer,
            review: request.responseType == .review ? answer : nil,
            followUpHint: followUpHint,
            oracleExportPath: nil,
            oracleExportInstruction: nil
        )
    }
}

struct HeadlessContextBuilderSelectedFile: Codable, Equatable {
    let path: String
    let tokens: Int
}

struct HeadlessContextBuilderOracleReply: Codable, Equatable {
    let chatID: String
    let shortID: String
    let mode: String
    let response: String?
    let errors: [String]?

    enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case shortID = "short_id"
        case mode
        case response
        case errors
    }
}

struct HeadlessContextBuilderResult: Codable, Equatable {
    let contextID: String
    let status: String
    let prompt: String
    let fileCount: Int
    let totalTokens: Int
    let tokenBudget: Int
    let promptMode: String
    let agent: String
    let agentExit: Int
    let selection: [HeadlessContextBuilderSelectedFile]
    let codemapFiles: [String]
    let responseType: String
    let plan: String?
    let review: String?
    let followUpHint: String?
    let oracleExportPath: String?
    let oracleExportInstruction: String?

    enum CodingKeys: String, CodingKey {
        case contextID = "context_id"
        case status
        case prompt
        case fileCount = "file_count"
        case totalTokens = "total_tokens"
        case tokenBudget = "token_budget"
        case promptMode = "prompt_mode"
        case agent
        case agentExit = "agent_exit"
        case selection
        case codemapFiles = "codemap_files"
        case responseType = "response_type"
        case plan
        case review
        case followUpHint = "follow_up_hint"
        case oracleExportPath = "oracle_export_path"
        case oracleExportInstruction = "oracle_export_instruction"
    }
}

actor HeadlessContextBuilderService {
    private let host: HeadlessWorkspaceHost
    private var activeRunID: String?

    init(host: HeadlessWorkspaceHost) {
        self.host = host
    }

    func run(request: HeadlessContextBuilderRequest, oracleService: OracleService) async throws -> HeadlessContextBuilderExecution {
        if activeRunID != nil {
            throw HeadlessToolFailure(message: "context_builder is already running")
        }
        guard !request.exportResponse else {
            throw HeadlessToolFailure(message: "export_response is not supported by rpce-headless context_builder yet.")
        }

        let runID = UUID().uuidString
        activeRunID = runID
        defer { activeRunID = nil }

        let prepared = try Self.prepareLaunch(request: request)
        let listener = HeadlessUnixSocketListener(path: prepared.socketPath)
        try listener.start { [host] fd in
            do {
                try await HeadlessMCPServer(host: host).runSocketConnection(fd: fd)
            } catch {
                fputs("rpce-headless socket connection: \(error.localizedDescription)\n", stderr)
            }
        }
        defer {
            listener.stop()
            try? FileManager.default.removeItem(at: prepared.tempDirectory)
        }

        let agentExit = try await runAgent(prepared.launch, timeoutSeconds: request.timeoutSeconds)
        let harvest = try await host.contextBuildHarvest()
        let oracle: (reply: HeadlessContextBuilderOracleReply?, answer: String?) = if agentExit == 0, !harvest.selectedFiles.isEmpty {
            try await runOracleFollowUpIfNeeded(request: request, harvest: harvest, oracleService: oracleService)
        } else {
            // Skip oracle spend when discovery failed or selected nothing; status reports agent_failed/empty_selection.
            (nil, nil)
        }

        return HeadlessContextBuilderExecution(
            contextID: runID,
            request: request,
            launch: prepared.launch,
            socketPath: prepared.socketPath,
            agentExit: agentExit,
            harvest: harvest,
            oracleReply: oracle.reply,
            answer: oracle.answer
        )
    }

    static func prepareLaunch(request: HeadlessContextBuilderRequest) throws -> (launch: RenderedAgentLaunch, socketPath: String, tempDirectory: URL) {
        let prompt = DiscoverPromptBuilder.build(
            instructions: request.instructions,
            tokenBudget: request.tokenBudget,
            responseType: request.responseType
        )
        let socketPath = request.socketPath ?? defaultContextBuilderSocketPath()
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rpce-headless-context-\(UUID().uuidString)", isDirectory: true)
        let launch = try AgentLauncher.render(
            agentName: request.agentName,
            configPath: request.agentConfigPath,
            prompt: prompt,
            socketPath: socketPath,
            executablePath: currentExecutablePath(),
            tempDirectory: tempDirectory
        )
        return (launch, socketPath, tempDirectory)
    }

    static func requestFromMCP(arguments: [String: MCP.Value], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> HeadlessContextBuilderRequest {
        guard let instructions = arguments["instructions"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !instructions.isEmpty else {
            throw HeadlessToolFailure(message: "missing instructions")
        }
        let rawResponseType = arguments["response_type"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "clarify"
        let responseType: ContextBuildResponseType
        switch rawResponseType {
        case "clarify": responseType = .selection
        case "question": responseType = .question
        case "plan": responseType = .plan
        case "review": responseType = .review
        default: throw HeadlessToolFailure(message: "response_type must be clarify, question, plan, or review")
        }

        let tokenBudget = arguments["token_budget"]?.intCoerced()
            ?? environment.trimmedInt("RPCE_CONTEXT_BUILDER_TOKEN_BUDGET")
            ?? (responseType == .selection ? 160_000 : 120_000)
        let timeoutSeconds = arguments["timeout_seconds"]?.intCoerced()
            ?? environment.trimmedInt("RPCE_CONTEXT_BUILDER_TIMEOUT_SECONDS")
            ?? 900
        let agentName = environment.trimmed("RPCE_CONTEXT_BUILDER_AGENT")
            ?? (environment.trimmed("FAKE_AGENT_SCRIPT") == nil ? "claude" : "fake")

        return HeadlessContextBuilderRequest(
            instructions: instructions,
            agentName: agentName,
            agentConfigPath: environment.trimmed("RPCE_CONTEXT_BUILDER_AGENT_CONFIG"),
            socketPath: environment.trimmed("RPCE_CONTEXT_BUILDER_SOCKET_PATH"),
            tokenBudget: tokenBudget,
            responseType: responseType,
            responseTypeName: rawResponseType,
            timeoutSeconds: timeoutSeconds,
            exportResponse: arguments["export_response"]?.boolCoerced() ?? false
        )
    }

    private func runOracleFollowUpIfNeeded(
        request: HeadlessContextBuilderRequest,
        harvest: HeadlessContextBuildHarvest,
        oracleService: OracleService
    ) async throws -> (reply: HeadlessContextBuilderOracleReply?, answer: String?) {
        guard request.responseType != .selection else { return (nil, nil) }
        let mode = switch request.responseType {
        case .selection: "chat"
        case .question: "chat"
        case .plan: "plan"
        case .review: "review"
        }
        let message = """
        Response mode: \(mode). \(Self.modeInstruction(for: request.responseType))

        User instructions:
        \(request.instructions)

        Discovery handoff:
        \(harvest.prompt)

        Workspace context:
        \(harvest.context)
        """
        let reply = try await oracleService.send(
            message: message,
            chatID: nil,
            model: nil,
            includeContext: false
        )
        var answer = ""
        for try await delta in reply.stream {
            answer += delta
        }
        let oracleReply = HeadlessContextBuilderOracleReply(
            chatID: reply.chatID,
            shortID: String(reply.chatID.prefix(8)),
            mode: mode,
            response: answer,
            errors: nil
        )
        return (oracleReply, answer)
    }

    private static func modeInstruction(for responseType: ContextBuildResponseType) -> String {
        switch responseType {
        case .selection:
            "Return only the selected context."
        case .question:
            "Answer the question directly."
        case .plan:
            "Produce a concrete implementation plan."
        case .review:
            "Produce a code review of the selected context."
        }
    }

    private func runAgent(_ launch: RenderedAgentLaunch, timeoutSeconds: Int) async throws -> Int32 {
        let process = Process()
        if launch.argv[0].contains("/") {
            process.executableURL = URL(fileURLWithPath: launch.argv[0])
            process.arguments = Array(launch.argv.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = launch.argv
        }
        process.environment = launch.environment

        let stdout = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdout
        process.standardError = stderrPipe
        prefixPipe(stdout, label: "agent|")
        prefixPipe(stderrPipe, label: "agent|")

        try process.run()
        setpgid(process.processIdentifier, process.processIdentifier)

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(max(1, timeoutSeconds)))
            if process.isRunning {
                kill(-process.processIdentifier, SIGTERM)
                process.terminate()
                try? await Task.sleep(for: .seconds(2))
                if process.isRunning {
                    kill(-process.processIdentifier, SIGKILL)
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        await Task.detached {
            process.waitUntilExit()
        }.value
        timeoutTask.cancel()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        return process.terminationStatus
    }

    private func prefixPipe(_ pipe: Pipe, label: String) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                guard !line.isEmpty else { continue }
                fputs("\(label) \(line)\n", stderr)
            }
        }
    }

    private static func currentExecutablePath() throws -> String {
        let arg0 = CommandLine.arguments[0]
        if arg0.contains("/") {
            let expanded = (arg0 as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") { return (expanded as NSString).standardizingPath }
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expanded)
                .standardizedFileURL
                .path
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(arg0).path
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        throw HeadlessCLI.ExitError(code: 69, message: "Unable to resolve current executable path")
    }
}

private func defaultContextBuilderSocketPath() -> String {
    "/tmp/rpce-headless-context-\(getpid())-\(UUID().uuidString).sock"
}

private extension [String: String] {
    func trimmed(_ key: String) -> String? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    func trimmedInt(_ key: String) -> Int? {
        trimmed(key).flatMap(Int.init)
    }
}
