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

enum HeadlessContextBuilderOperation: String, Equatable {
    case synchronous
    case start
    case poll
    case wait
    case getResult = "get_result"
    case cancel
    case cleanup
}

struct HeadlessContextBuilderToolRequest {
    let operation: HeadlessContextBuilderOperation
    let contextID: String?
    let waitTimeoutSeconds: Int
    let request: HeadlessContextBuilderRequest?
}

typealias HeadlessProgressReporter = @Sendable (_ progress: Double, _ total: Double?, _ message: String) async -> Void

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
    private final class AsyncRunRecord {
        let id: String
        let request: HeadlessContextBuilderRequest
        let launch: RenderedAgentLaunch
        let socketPath: String
        let tempDirectory: URL
        let discoveryHost: HeadlessWorkspaceHost
        let listener: HeadlessUnixSocketListener
        let stdoutPipe: Pipe
        let stderrPipe: Pipe
        let startedAt: Date

        var updatedAt: Date
        var status: HeadlessContextBuilderRunStatus
        var processID: Int32?
        var reaperTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
        var escalationTask: Task<Void, Never>?
        var exitCode: Int32?
        var result: HeadlessContextBuilderResult?
        var error: String?
        var cancellationRequested: Bool
        var resourcesClosed: Bool
        var stdout: String
        var stderr: String
        var stdoutTruncated: Bool
        var stderrTruncated: Bool
        var terminationStatus: String?

        init(
            id: String,
            request: HeadlessContextBuilderRequest,
            launch: RenderedAgentLaunch,
            socketPath: String,
            tempDirectory: URL,
            discoveryHost: HeadlessWorkspaceHost,
            listener: HeadlessUnixSocketListener,
            stdoutPipe: Pipe,
            stderrPipe: Pipe,
            now: Date
        ) {
            self.id = id
            self.request = request
            self.launch = launch
            self.socketPath = socketPath
            self.tempDirectory = tempDirectory
            self.discoveryHost = discoveryHost
            self.listener = listener
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            startedAt = now
            updatedAt = now
            status = .running
            processID = nil
            reaperTask = nil
            timeoutTask = nil
            escalationTask = nil
            exitCode = nil
            result = nil
            error = nil
            cancellationRequested = false
            resourcesClosed = false
            stdout = ""
            stderr = ""
            stdoutTruncated = false
            stderrTruncated = false
            terminationStatus = nil
        }
    }

    private enum OutputStreamKind {
        case stdout
        case stderr
    }

    private let host: HeadlessWorkspaceHost
    private let outputCaptureLimitBytes: Int
    private var activeRunID: String?
    private var latestRunID: String?
    private var asyncRuns: [String: AsyncRunRecord] = [:]

    init(
        host: HeadlessWorkspaceHost,
        outputCaptureLimitBytes: Int = HeadlessContextBuilderService.outputCaptureLimitBytesFromEnvironment()
    ) {
        self.host = host
        self.outputCaptureLimitBytes = outputCaptureLimitBytes
    }

    func execute(
        arguments: [String: MCP.Value],
        oracleService: OracleService,
        progressReporter: HeadlessProgressReporter? = nil
    ) async throws -> CallTool.Result {
        let toolRequest = try Self.toolRequestFromMCP(arguments: arguments)
        switch toolRequest.operation {
        case .synchronous:
            guard let request = toolRequest.request else { throw HeadlessToolFailure(message: "missing context_builder request") }
            return try await startAndWaitForSynchronousRequest(request: request, oracleService: oracleService, progressReporter: progressReporter)
        case .start:
            guard let request = toolRequest.request else { throw HeadlessToolFailure(message: "missing context_builder request") }
            await progressReporter?(0, 1, "Starting context_builder discovery...")
            let snapshot = try await start(request: request, oracleService: oracleService)
            await progressReporter?(1, 1, "context_builder started with context_id \(snapshot.contextID). Poll or wait for progress.")
            return try jsonTextResult(snapshot)
        case .poll:
            return try jsonTextResult(poll(contextID: try requireContextID(toolRequest)))
        case .wait:
            return try await jsonTextResult(wait(contextID: try requireContextID(toolRequest), timeoutSeconds: toolRequest.waitTimeoutSeconds, progressReporter: progressReporter))
        case .getResult:
            return try resultTool(contextID: try requireContextID(toolRequest))
        case .cancel:
            return try await jsonTextResult(cancel(contextID: try requireContextID(toolRequest)))
        case .cleanup:
            return try jsonTextResult(cleanup(contextID: try requireContextID(toolRequest)))
        }
    }

    private func startAndWaitForSynchronousRequest(
        request: HeadlessContextBuilderRequest,
        oracleService: OracleService,
        progressReporter: HeadlessProgressReporter?
    ) async throws -> CallTool.Result {
        await progressReporter?(0, 1, "Starting context_builder discovery...")
        let started = try await start(request: request, oracleService: oracleService)
        let waitSeconds = min(request.timeoutSeconds, Self.synchronousMCPWaitTimeoutSeconds())
        let snapshot = await wait(contextID: started.contextID, timeoutSeconds: waitSeconds, progressReporter: progressReporter)
        guard snapshot.runStatus == HeadlessContextBuilderRunStatus.completed.rawValue ||
            snapshot.runStatus == HeadlessContextBuilderRunStatus.failed.rawValue ||
            snapshot.runStatus == HeadlessContextBuilderRunStatus.cancelled.rawValue
        else {
            return try jsonTextResult(snapshot)
        }
        let result = try resultTool(contextID: started.contextID)
        if let record = asyncRuns[started.contextID], record.status == .completed {
            discardTerminalRecord(record)
        }
        return result
    }

    func shutdown() async {
        let records = Array(asyncRuns.values)
        for record in records where !record.status.isTerminal {
            requestCancellation(for: record)
            terminate(record: record)
        }

        await waitForShutdownProgress(records, timeoutSeconds: 3)

        for record in records where !record.status.isTerminal {
            if let processID = record.processID {
                terminateProcessTree(processID: processID)
            }
        }

        await waitForShutdownProgress(records, timeoutSeconds: 3)

        for record in records {
            if !record.status.isTerminal {
                record.error = "context_builder discovery was cancelled during server shutdown"
                record.status = .cancelled
                record.updatedAt = Date()
            }
            closeResources(for: record)
        }
        activeRunID = nil
        latestRunID = nil
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

    private func start(request: HeadlessContextBuilderRequest, oracleService: OracleService) async throws -> HeadlessContextBuilderRunSnapshot {
        if let activeRunID {
            if let active = asyncRuns[activeRunID] {
                if !active.status.isTerminal || !active.resourcesClosed {
                    throw HeadlessToolFailure(message: "context_builder is already running with context_id '\(activeRunID)'; poll, wait, get_result, cancel, or cleanup that run before starting another.")
                }
                self.activeRunID = nil
            } else {
                throw HeadlessToolFailure(message: "context_builder is already running")
            }
        }
        guard !request.exportResponse else {
            throw HeadlessToolFailure(message: "export_response is not supported by rpce-headless context_builder yet.")
        }

        let runID = UUID().uuidString
        let prepared = try Self.prepareLaunch(request: request)
        let discoveryHost = try await makeDiscoveryHost()
        let listener = HeadlessUnixSocketListener(path: prepared.socketPath)
        try listener.start { [discoveryHost] fd in
            do {
                try await HeadlessMCPServer(host: discoveryHost).runSocketConnection(fd: fd)
            } catch {
                fputs("rpce-headless socket connection: \(error.localizedDescription)\n", stderr)
            }
        }

        let stdout = Pipe()
        let stderrPipe = Pipe()

        let now = Date()
        let record = AsyncRunRecord(
            id: runID,
            request: request,
            launch: prepared.launch,
            socketPath: prepared.socketPath,
            tempDirectory: prepared.tempDirectory,
            discoveryHost: discoveryHost,
            listener: listener,
            stdoutPipe: stdout,
            stderrPipe: stderrPipe,
            now: now
        )
        asyncRuns[runID] = record
        activeRunID = runID
        latestRunID = runID

        capturePipe(stdout, contextID: runID, stream: .stdout, label: "agent|")
        capturePipe(stderrPipe, contextID: runID, stream: .stderr, label: "agent|")

        do {
            let spawned = try HeadlessProcessGroupLauncher.spawn(
                argv: prepared.launch.argv,
                environment: prepared.launch.environment,
                stdoutWriteFD: stdout.fileHandleForWriting.fileDescriptor,
                stderrWriteFD: stderrPipe.fileHandleForWriting.fileDescriptor
            )
            stdout.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
            record.processID = spawned.pid
            record.reaperTask = Task.detached { [runID] in
                let exitCode = HeadlessProcessGroupLauncher.reapExitCode(pid: spawned.pid)
                await self.completeAsyncRun(contextID: runID, exitCode: exitCode, oracleService: oracleService)
            }
            record.timeoutTask = Task { [runID, timeoutSeconds = request.timeoutSeconds, processID = spawned.pid] in
                do {
                    try await Task.sleep(for: .seconds(max(1, timeoutSeconds)))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.timeoutAsyncRun(contextID: runID, processID: processID)
            }
            record.updatedAt = Date()
        } catch {
            asyncRuns[runID] = nil
            activeRunID = nil
            if latestRunID == runID { latestRunID = nil }
            listener.stop()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdout.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            try? stdout.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            try? FileManager.default.removeItem(at: prepared.tempDirectory)
            throw error
        }

        return snapshot(for: record)
    }

    private func poll(contextID: String) -> HeadlessContextBuilderRunSnapshot {
        guard let resolved = resolveContextID(contextID) else { return expiredSnapshot(contextID: contextID) }
        guard let record = asyncRuns[resolved] else { return expiredSnapshot(contextID: resolved) }
        return snapshot(for: record)
    }

    private func wait(
        contextID: String,
        timeoutSeconds: Int,
        progressReporter: HeadlessProgressReporter? = nil
    ) async -> HeadlessContextBuilderRunSnapshot {
        guard let resolved = resolveContextID(contextID) else { return expiredSnapshot(contextID: contextID) }
        if timeoutSeconds <= 0 {
            guard let record = asyncRuns[resolved] else { return expiredSnapshot(contextID: resolved) }
            return snapshot(for: record)
        }
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var lastProgressAt = Date.distantPast
        while true {
            guard let record = asyncRuns[resolved] else { return expiredSnapshot(contextID: resolved) }
            if record.status.isTerminal { return snapshot(for: record) }
            let now = Date()
            if now.timeIntervalSince(lastProgressAt) >= 5 {
                let elapsed = max(0, Int(now.timeIntervalSince(record.startedAt).rounded(.down)))
                await progressReporter?(
                    Double(min(elapsed, timeoutSeconds)),
                    Double(timeoutSeconds),
                    "\(statusText(for: record)) Elapsed \(elapsed)s; poll or wait again with context_id \(record.id)."
                )
                lastProgressAt = now
            }
            if Date() >= deadline { return snapshot(for: record, waitResult: "timed_out") }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func makeDiscoveryHost() async throws -> HeadlessWorkspaceHost {
        let roots = await host.rootsText()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return try await HeadlessWorkspaceHost(rootPaths: roots)
    }

    private func resultTool(contextID: String) throws -> CallTool.Result {
        let resolved = resolveContextID(contextID) ?? contextID
        guard let record = asyncRuns[resolved] else {
            throw HeadlessToolFailure(message: "Unknown or cleaned up context_builder context_id '\(contextID)'.")
        }
        guard record.status.isTerminal else {
            throw HeadlessToolFailure(message: "context_builder context_id '\(contextID)' is not ready; current run_status is \(record.status.rawValue).")
        }
        guard record.status == .completed, let result = record.result else {
            let snapshot = snapshot(for: record)
            return try CallTool.Result(
                content: [.text(text: failedResultMessage(for: record), annotations: nil, _meta: nil)],
                structuredContent: snapshot,
                isError: true
            )
        }
        return try jsonTextResult(result)
    }

    private func cancel(contextID: String) async -> HeadlessContextBuilderRunSnapshot {
        guard let resolved = resolveContextID(contextID) else { return expiredSnapshot(contextID: contextID) }
        guard let record = asyncRuns[resolved] else { return expiredSnapshot(contextID: resolved) }
        guard !record.status.isTerminal else { return snapshot(for: record) }
        requestCancellation(for: record)
        if record.processID == nil {
            record.reaperTask?.cancel()
            record.reaperTask = nil
            finishCancelled(record)
        } else {
            terminate(record: record)
        }
        return await wait(contextID: resolved, timeoutSeconds: 5)
    }

    private func cleanup(contextID: String) throws -> HeadlessContextBuilderCleanupReply {
        let resolved = resolveContextID(contextID) ?? contextID
        guard let record = asyncRuns[resolved] else {
            return HeadlessContextBuilderCleanupReply(
                status: "partial",
                deletedCount: 0,
                skippedCount: 1,
                deletedContexts: [],
                skippedContexts: [.init(contextID: contextID, reason: "not_found")]
            )
        }
        guard record.status.isTerminal else {
            return HeadlessContextBuilderCleanupReply(
                status: "partial",
                deletedCount: 0,
                skippedCount: 1,
                deletedContexts: [],
                skippedContexts: [.init(contextID: record.id, reason: "skipped_active")]
            )
        }
        closeResources(for: record)
        asyncRuns[record.id] = nil
        if activeRunID == record.id { activeRunID = nil }
        if latestRunID == record.id { latestRunID = nil }
        try? FileManager.default.removeItem(at: record.tempDirectory)
        return HeadlessContextBuilderCleanupReply(
            status: "completed",
            deletedCount: 1,
            skippedCount: 0,
            deletedContexts: [.init(contextID: record.id, reason: nil)],
            skippedContexts: []
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

    static func toolRequestFromMCP(arguments: [String: MCP.Value], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> HeadlessContextBuilderToolRequest {
        let rawOp = arguments["op"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let operation: HeadlessContextBuilderOperation
        if let rawOp, !rawOp.isEmpty {
            guard let parsed = HeadlessContextBuilderOperation(rawValue: rawOp) else {
                throw HeadlessToolFailure(message: "Unsupported context_builder op '\(rawOp)'. Use start, poll, wait, get_result, cancel, or cleanup.")
            }
            operation = parsed
        } else {
            operation = .synchronous
        }

        switch operation {
        case .synchronous, .start:
            return HeadlessContextBuilderToolRequest(
                operation: operation,
                contextID: nil,
                waitTimeoutSeconds: 0,
                request: try requestFromMCP(arguments: arguments, environment: environment)
            )
        case .poll, .wait, .getResult, .cancel, .cleanup:
            let contextID = try requireNonEmptyString(arguments["context_id"], name: "context_id")
            let requestedWaitTimeout = arguments["timeout"]?.intCoerced()
                ?? arguments["timeout_seconds"]?.intCoerced()
                ?? Self.defaultLifecycleWaitTimeoutSeconds(environment)
            return HeadlessContextBuilderToolRequest(
                operation: operation,
                contextID: contextID,
                waitTimeoutSeconds: Self.cappedLifecycleWaitTimeout(requestedWaitTimeout, environment: environment),
                request: nil
            )
        }
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

    private static func requireNonEmptyString(_ value: MCP.Value?, name: String) throws -> String {
        guard let raw = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw HeadlessToolFailure(message: "\(name) is required and must be a non-empty string.")
        }
        return raw
    }

    private func requireContextID(_ request: HeadlessContextBuilderToolRequest) throws -> String {
        guard let contextID = request.contextID, !contextID.isEmpty else {
            throw HeadlessToolFailure(message: "context_id is required and must be a non-empty string.")
        }
        return contextID
    }

    private func resolveContextID(_ contextID: String) -> String? {
        let trimmed = contextID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "active" || trimmed == "current" {
            return activeRunID ?? latestRunID
        }
        return trimmed
    }

    private static func synchronousMCPWaitTimeoutSeconds(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        max(0, environment.headlessTrimmedInt("RPCE_CONTEXT_BUILDER_SYNC_WAIT_TIMEOUT_SECONDS") ?? 90)
    }

    static func defaultLifecycleWaitTimeoutSeconds(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        max(0, environment.headlessTrimmedInt("RPCE_CONTEXT_BUILDER_WAIT_DEFAULT_SECONDS") ?? 15)
    }

    static func maxLifecycleWaitTimeoutSeconds(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        max(1, environment.headlessTrimmedInt("RPCE_CONTEXT_BUILDER_WAIT_MAX_SECONDS") ?? 30)
    }

    static func cappedLifecycleWaitTimeout(
        _ requested: Int,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        let requested = max(0, requested)
        guard requested > 0 else { return 0 }
        return min(requested, maxLifecycleWaitTimeoutSeconds(environment))
    }

    private func waitForShutdownProgress(_ records: [AsyncRunRecord], timeoutSeconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while records.contains(where: { !$0.status.isTerminal && !$0.resourcesClosed }) {
            if Date() >= deadline { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func completeAsyncRun(contextID: String, exitCode: Int32, oracleService: OracleService) async {
        guard let record = asyncRuns[contextID] else { return }
        record.exitCode = exitCode
        record.updatedAt = Date()
        if !record.status.isTerminal {
            record.processID = nil
        }
        guard !record.resourcesClosed else {
            if activeRunID == contextID { activeRunID = nil }
            return
        }
        drainPipes(for: record)
        record.timeoutTask?.cancel()
        record.timeoutTask = nil

        if record.status.isTerminal {
            if activeRunID == contextID { activeRunID = nil }
            closeResources(for: record)
            return
        }

        if record.status == .cancelling {
            finishCancelled(record)
            return
        }

        do {
            let harvest = try await record.discoveryHost.contextBuildHarvest()
            if record.status.isTerminal || Task.isCancelled {
                closeResources(for: record)
                if activeRunID == contextID { activeRunID = nil }
                return
            }
            if record.status == .cancelling {
                finishCancelled(record)
                return
            }
            let oracle: (reply: HeadlessContextBuilderOracleReply?, answer: String?) = if exitCode == 0, !harvest.selectedFiles.isEmpty {
                try await runOracleFollowUpIfNeeded(request: record.request, harvest: harvest, oracleService: oracleService)
            } else {
                (nil, nil)
            }
            if record.status.isTerminal || Task.isCancelled {
                closeResources(for: record)
                if activeRunID == contextID { activeRunID = nil }
                return
            }
            if record.status == .cancelling {
                finishCancelled(record)
                return
            }
            let execution = HeadlessContextBuilderExecution(
                contextID: contextID,
                request: record.request,
                launch: record.launch,
                socketPath: record.socketPath,
                agentExit: exitCode,
                harvest: harvest,
                oracleReply: oracle.reply,
                answer: oracle.answer
            )
            record.result = execution.mcpResult
            record.status = .completed
            record.updatedAt = Date()
            if activeRunID == contextID { activeRunID = nil }
            closeResources(for: record)
        } catch {
            if record.status.isTerminal {
                closeResources(for: record)
                if activeRunID == contextID { activeRunID = nil }
                return
            }
            if record.status == .cancelling || Task.isCancelled {
                record.error = record.error ?? "context_builder discovery was cancelled"
                finishCancelled(record)
                return
            }
            record.error = error.localizedDescription
            record.status = .failed
            record.updatedAt = Date()
            if activeRunID == contextID { activeRunID = nil }
            closeResources(for: record)
        }
    }

    private func discardTerminalRecord(_ record: AsyncRunRecord) {
        guard record.status.isTerminal else { return }
        closeResources(for: record)
        asyncRuns[record.id] = nil
        if activeRunID == record.id { activeRunID = nil }
        if latestRunID == record.id { latestRunID = nil }
        try? FileManager.default.removeItem(at: record.tempDirectory)
    }

    private func timeoutAsyncRun(contextID: String, processID: pid_t) {
        guard let record = asyncRuns[contextID], !record.status.isTerminal else { return }
        record.error = "context_builder discovery timed out after \(record.request.timeoutSeconds) seconds"
        record.status = .failed
        record.updatedAt = Date()
        record.terminationStatus = "sigkill_requested_after_timeout"
        record.listener.stop()
        terminateProcessTree(processID: processID)
    }

    private func requestCancellation(for record: AsyncRunRecord) {
        record.cancellationRequested = true
        record.status = .cancelling
        record.updatedAt = Date()
    }

    private func finishCancelled(_ record: AsyncRunRecord) {
        record.reaperTask?.cancel()
        record.reaperTask = nil
        record.escalationTask?.cancel()
        record.escalationTask = nil
        record.timeoutTask?.cancel()
        record.timeoutTask = nil
        record.status = .cancelled
        record.updatedAt = Date()
        if activeRunID == record.id { activeRunID = nil }
        closeResources(for: record)
    }

    private func snapshot(for record: AsyncRunRecord, waitResult: String? = nil) -> HeadlessContextBuilderRunSnapshot {
        HeadlessContextBuilderRunSnapshot(
            contextID: record.id,
            runStatus: record.status.rawValue,
            statusText: statusText(for: record),
            startedAt: timestamp(record.startedAt),
            updatedAt: timestamp(record.updatedAt),
            elapsedSeconds: max(0, Int(Date().timeIntervalSince(record.startedAt).rounded(.down))),
            agent: record.request.agentName,
            responseType: record.request.responseTypeName,
            processID: record.processID.map(Int.init),
            resultStatus: record.result?.status,
            error: record.error,
            nextAction: nextAction(for: record),
            diagnostics: diagnostics(for: record),
            meta: waitResult.map { .init(waitResult: $0) }
        )
    }

    private func expiredSnapshot(contextID: String) -> HeadlessContextBuilderRunSnapshot {
        let now = Date()
        return HeadlessContextBuilderRunSnapshot(
            contextID: contextID,
            runStatus: HeadlessContextBuilderRunStatus.expired.rawValue,
            statusText: "context_builder run is unavailable or expired.",
            startedAt: nil,
            updatedAt: timestamp(now),
            elapsedSeconds: nil,
            agent: "unknown",
            responseType: "unknown",
            processID: nil,
            resultStatus: nil,
            error: nil,
            nextAction: "Start a new context_builder run with op:\"start\", or use a context_id returned by an active/latest run before cleanup.",
            diagnostics: nil,
            meta: nil
        )
    }

    private func statusText(for record: AsyncRunRecord) -> String {
        switch record.status {
        case .running:
            "context_builder discovery is running."
        case .cancelling:
            "context_builder discovery is cancelling."
        case .completed:
            "context_builder discovery completed."
        case .failed:
            "context_builder discovery failed\(record.error.map { ": \($0)" } ?? ".")"
        case .cancelled:
            "context_builder discovery was cancelled."
        case .expired:
            "context_builder run is unavailable or expired."
        }
    }

    private func nextAction(for record: AsyncRunRecord) -> String? {
        switch record.status {
        case .running:
            "Call context_builder with op:\"poll\" for an immediate snapshot, op:\"wait\" with a short timeout for progress, or op:\"cancel\" to stop this run. You may use context_id:\"active\" or \"current\" for this run."
        case .cancelling:
            "Poll or wait briefly until cancellation reaches a terminal state."
        case .completed:
            "Call context_builder with op:\"get_result\" and this context_id, or context_id:\"active\"/\"current\" while it remains the latest run, then op:\"cleanup\" when done."
        case .failed, .cancelled:
            "Inspect diagnostics with this snapshot or get_result, then call op:\"cleanup\" when done."
        case .expired:
            nil
        }
    }

    private func timestamp(_ date: Date) -> String {
        DateFormatter.headlessAgentISO8601.string(from: date)
    }

    private func drainPipes(for record: AsyncRunRecord) {
        record.stdoutPipe.fileHandleForReading.readabilityHandler = nil
        record.stderrPipe.fileHandleForReading.readabilityHandler = nil
        drainPipe(record.stdoutPipe, contextID: record.id, stream: .stdout)
        drainPipe(record.stderrPipe, contextID: record.id, stream: .stderr)
    }

    private func closeResources(for record: AsyncRunRecord) {
        guard !record.resourcesClosed else { return }
        record.resourcesClosed = true
        record.listener.stop()
        record.stdoutPipe.fileHandleForReading.readabilityHandler = nil
        record.stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? record.stdoutPipe.fileHandleForReading.close()
        try? record.stderrPipe.fileHandleForReading.close()
        try? FileManager.default.removeItem(at: record.tempDirectory)
        record.timeoutTask?.cancel()
        record.timeoutTask = nil
        record.escalationTask?.cancel()
        record.escalationTask = nil
    }

    private func terminate(record: AsyncRunRecord) {
        guard record.escalationTask == nil else { return }
        guard let processID = record.processID, processID > 0 else { return }
        record.terminationStatus = "sigterm_requested"
        kill(-processID, SIGTERM)
        kill(processID, SIGTERM)
        record.escalationTask = Task {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            terminateProcessTree(processID: processID)
        }
    }

    private nonisolated func terminateProcessTree(processID: pid_t) {
        guard processID > 0 else { return }
        kill(-processID, SIGKILL)
        kill(processID, SIGKILL)
    }

    private func jsonTextResult(_ value: some Codable) throws -> CallTool.Result {
        try CallTool.Result(
            content: [.text(text: HeadlessJSON.string(value), annotations: nil, _meta: nil)],
            structuredContent: value,
            isError: false
        )
    }

    private static func outputCaptureLimitBytesFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        environment.headlessTrimmedInt("RPCE_CONTEXT_BUILDER_OUTPUT_CAPTURE_LIMIT_BYTES")
            ?? environment.headlessTrimmedInt("RPCE_AGENT_OUTPUT_CAPTURE_LIMIT_BYTES")
            ?? 1_000_000
    }

    private func capturePipe(_ pipe: Pipe, contextID: String, stream: OutputStreamKind, label: String) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            Self.forwardPrefixed(text, label: label)
            Task { await self.appendOutput(contextID: contextID, stream: stream, text: text) }
        }
    }

    private func drainPipe(_ pipe: Pipe, contextID: String, stream: OutputStreamKind) {
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return }
        guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { return }
        defer { _ = fcntl(fd, F_SETFL, flags) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                let data = Data(buffer.prefix(Int(count)))
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                Self.forwardPrefixed(text, label: "agent|")
                appendOutput(contextID: contextID, stream: stream, text: text)
            } else {
                return
            }
        }
    }

    private func appendOutput(contextID: String, stream: OutputStreamKind, text: String) {
        guard let record = asyncRuns[contextID] else { return }
        switch stream {
        case .stdout:
            append(text, to: &record.stdout, truncated: &record.stdoutTruncated)
        case .stderr:
            append(text, to: &record.stderr, truncated: &record.stderrTruncated)
        }
        record.updatedAt = Date()
    }

    private func append(_ text: String, to output: inout String, truncated: inout Bool) {
        guard !text.isEmpty, outputCaptureLimitBytes > 0 else { return }
        let existing = output.data(using: .utf8)?.count ?? output.utf8.count
        let incoming = text.data(using: .utf8)?.count ?? text.utf8.count
        let allowed = outputCaptureLimitBytes - existing
        if allowed <= 0 {
            truncated = true
            return
        }
        if incoming <= allowed {
            output += text
            return
        }
        output += utf8Prefix(text, byteLimit: allowed)
        truncated = true
    }

    private func utf8Prefix(_ text: String, byteLimit: Int) -> String {
        guard byteLimit > 0 else { return "" }
        var result = String()
        result.reserveCapacity(min(text.count, byteLimit))
        var usedBytes = 0
        for scalar in text.unicodeScalars {
            let scalarText = String(scalar)
            let byteCount = scalarText.utf8.count
            guard usedBytes + byteCount <= byteLimit else { break }
            result.unicodeScalars.append(scalar)
            usedBytes += byteCount
        }
        return result
    }

    private func diagnostics(for record: AsyncRunRecord) -> HeadlessContextBuilderDiagnostics? {
        let outputEmpty = record.stdout.isEmpty && record.stderr.isEmpty
        let hasCapturedOutput = !outputEmpty || record.stdoutTruncated || record.stderrTruncated
        let shouldReportQuietFailure = record.status == .failed
        guard hasCapturedOutput || shouldReportQuietFailure else {
            return nil
        }
        return HeadlessContextBuilderDiagnostics(
            stdout: record.stdout,
            stderr: record.stderr,
            stdoutTruncated: record.stdoutTruncated,
            stderrTruncated: record.stderrTruncated,
            outputCaptureLimitBytes: outputCaptureLimitBytes,
            outputCaptureEnabled: outputCaptureLimitBytes > 0,
            outputEmpty: outputEmpty,
            timeoutSeconds: record.request.timeoutSeconds,
            processID: record.processID.map(Int.init),
            terminationStatus: record.terminationStatus
        )
    }

    private func failedResultMessage(for record: AsyncRunRecord) -> String {
        var parts = [
            "context_builder context_id '\(record.id)' did not complete successfully; run_status is \(record.status.rawValue)."
        ]
        if let error = record.error, !error.isEmpty {
            parts.append("error: \(error)")
        }
        if let diagnostics = diagnostics(for: record) {
            parts.append("diagnostics: stdout_truncated=\(diagnostics.stdoutTruncated), stderr_truncated=\(diagnostics.stderrTruncated), output_empty=\(diagnostics.outputEmpty), output_capture_limit_bytes=\(diagnostics.outputCaptureLimitBytes)")
            if let timeoutSeconds = diagnostics.timeoutSeconds {
                parts.append("timeout_seconds: \(timeoutSeconds)")
            }
            if let processID = diagnostics.processID {
                parts.append("process_id: \(processID)")
            }
            if let terminationStatus = diagnostics.terminationStatus {
                parts.append("termination_status: \(terminationStatus)")
            }
            if !diagnostics.stdout.isEmpty {
                parts.append("stdout_excerpt: \(diagnosticExcerpt(diagnostics.stdout))")
            }
            if !diagnostics.stderr.isEmpty {
                parts.append("stderr_excerpt: \(diagnosticExcerpt(diagnostics.stderr))")
            }
        }
        return parts.joined(separator: "\n")
    }

    private func diagnosticExcerpt(_ text: String) -> String {
        utf8Prefix(text, byteLimit: 4_096)
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
        let stdout = Pipe()
        let stderrPipe = Pipe()
        prefixPipe(stdout, label: "agent|")
        prefixPipe(stderrPipe, label: "agent|")

        let spawned: HeadlessProcessGroupLauncher.SpawnedProcess
        do {
            spawned = try HeadlessProcessGroupLauncher.spawn(
                argv: launch.argv,
                environment: launch.environment,
                stdoutWriteFD: stdout.fileHandleForWriting.fileDescriptor,
                stderrWriteFD: stderrPipe.fileHandleForWriting.fileDescriptor
            )
            stdout.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdout.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
            try? stdout.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            throw error
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(max(1, timeoutSeconds)))
            guard kill(spawned.pid, 0) == 0 else { return }
            kill(-spawned.pid, SIGTERM)
            kill(spawned.pid, SIGTERM)
            try? await Task.sleep(for: .seconds(2))
            if kill(spawned.pid, 0) == 0 {
                kill(-spawned.pid, SIGKILL)
                kill(spawned.pid, SIGKILL)
            }
        }

        let exitCode = await Task.detached {
            HeadlessProcessGroupLauncher.reapExitCode(pid: spawned.pid)
        }.value
        timeoutTask.cancel()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdout.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
        return exitCode
    }

    private func prefixPipe(_ pipe: Pipe, label: String) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            Self.forwardPrefixed(text, label: label)
        }
    }

    private static func forwardPrefixed(_ text: String, label: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard !line.isEmpty else { continue }
            fputs("\(label) \(line)\n", stderr)
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
