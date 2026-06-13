import Foundation
import MCP

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

actor HeadlessAgentSessionManager {
    private final class SessionRecord {
        let id: String
        let name: String
        let agentName: String
        let modelID: String
        let prompt: String
        let tempDirectory: URL
        let promptPath: String
        let mcpConfigPath: String
        let startedAt: Date
        let process: Process
        let stdoutPipe: Pipe
        let stderrPipe: Pipe

        var updatedAt: Date
        var status: HeadlessAgentRunStatus
        var processID: Int32?
        var exitCode: Int32?
        var cancellationRequested: Bool
        var stdout: String
        var stderr: String
        var stdoutTruncated: Bool
        var stderrTruncated: Bool

        init(
            id: String,
            name: String,
            agentName: String,
            modelID: String,
            prompt: String,
            tempDirectory: URL,
            promptPath: String,
            mcpConfigPath: String,
            process: Process,
            stdoutPipe: Pipe,
            stderrPipe: Pipe,
            now: Date
        ) {
            self.id = id
            self.name = name
            self.agentName = agentName
            self.modelID = modelID
            self.prompt = prompt
            self.tempDirectory = tempDirectory
            self.promptPath = promptPath
            self.mcpConfigPath = mcpConfigPath
            self.process = process
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            startedAt = now
            updatedAt = now
            status = .running
            processID = nil
            exitCode = nil
            cancellationRequested = false
            stdout = ""
            stderr = ""
            stdoutTruncated = false
            stderrTruncated = false
        }
    }

    private enum OutputStreamKind {
        case stdout
        case stderr
    }

    private let host: HeadlessWorkspaceHost
    private let configuration: HeadlessAgentRuntimeConfiguration
    private var sessions: [String: SessionRecord] = [:]
    private var listener: HeadlessUnixSocketListener?
    private var socketPath: String?
    private var socketTempDirectory: URL?

    init(
        host: HeadlessWorkspaceHost,
        configuration: HeadlessAgentRuntimeConfiguration = .fromEnvironment()
    ) {
        self.host = host
        self.configuration = configuration
    }

    func executeAgentRun(arguments: [String: MCP.Value]) async throws -> CallTool.Result {
        let op = arguments["op"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "wait"
        switch op {
        case "start":
            return try await jsonTextResult(startRun(arguments: arguments))
        case "poll":
            return try jsonTextResult(pollRun(arguments: arguments))
        case "wait":
            return try await jsonTextResult(waitRun(arguments: arguments))
        case "cancel":
            return try await jsonTextResult(cancelRun(arguments: arguments))
        default:
            throw HeadlessToolFailure(message: "Unsupported headless agent_run op '\(op)'. Use start, poll, wait, or cancel.")
        }
    }

    func executeAgentManage(arguments: [String: MCP.Value]) async throws -> CallTool.Result {
        guard let op = arguments["op"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !op.isEmpty else {
            throw HeadlessToolFailure(message: "agent_manage op is required. Use list_agents, list_sessions, get_log, stop_session, or cleanup_sessions.")
        }
        switch op {
        case "list_agents":
            return try jsonTextResult(listAgents())
        case "list_sessions":
            return try jsonTextResult(listSessions(arguments: arguments))
        case "get_log":
            return try jsonTextResult(getLog(arguments: arguments))
        case "stop_session":
            return try await jsonTextResult(stopSession(arguments: arguments))
        case "cleanup_sessions":
            return try jsonTextResult(cleanupSessions(arguments: arguments))
        default:
            throw HeadlessToolFailure(message: "Unsupported headless agent_manage op '\(op)'. Use list_agents, list_sessions, get_log, stop_session, or cleanup_sessions.")
        }
    }

    func shutdown() async {
        for record in sessions.values where !record.status.isTerminal {
            record.cancellationRequested = true
            terminate(record.process)
        }
        listener?.stop()
        listener = nil
        if let socketTempDirectory {
            try? FileManager.default.removeItem(at: socketTempDirectory)
        }
    }

    private func startRun(arguments: [String: MCP.Value]) async throws -> HeadlessAgentRunSnapshot {
        try rejectUnsupportedStartArguments(arguments)
        let message = try requireNonEmptyString(arguments["message"], name: "message")
        let agentName = arguments["model_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? configuration.defaultAgentName
        let definitions = try AgentLauncher.definitions(configPath: configuration.agentConfigPath)
        guard definitions[agentName] != nil else {
            throw HeadlessToolFailure(message: "Unknown headless agent '\(agentName)'. Available agents: \(definitions.keys.sorted().joined(separator: ", "))")
        }

        let sessionID = UUID().uuidString
        let sessionName = arguments["session_name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Headless agent \(String(sessionID.prefix(8)))"
        let socketPath = try ensureSocketServer()
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rpce-headless-agent-\(sessionID)", isDirectory: true)
        let launch = try AgentLauncher.render(
            agentName: agentName,
            configPath: configuration.agentConfigPath,
            prompt: message,
            socketPath: socketPath,
            executablePath: currentHeadlessExecutablePath(),
            tempDirectory: tempDirectory
        )

        let process = Process()
        if launch.argv[0].contains("/") {
            process.executableURL = URL(fileURLWithPath: launch.argv[0])
            process.arguments = Array(launch.argv.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = launch.argv
        }
        process.environment = launch.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let now = Date()
        let record = SessionRecord(
            id: sessionID,
            name: sessionName,
            agentName: agentName,
            modelID: agentName,
            prompt: message,
            tempDirectory: tempDirectory,
            promptPath: launch.promptPath,
            mcpConfigPath: launch.mcpConfigPath,
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            now: now
        )
        sessions[sessionID] = record

        stdoutPipe.fileHandleForReading.readabilityHandler = { [sessionID] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self.appendOutput(sessionID: sessionID, stream: .stdout, data: data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [sessionID] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self.appendOutput(sessionID: sessionID, stream: .stderr, data: data) }
        }
        process.terminationHandler = { [sessionID] process in
            Task { await self.completeSession(sessionID: sessionID, exitCode: process.terminationStatus) }
        }

        do {
            try process.run()
            setProcessGroup(for: process)
            record.processID = process.processIdentifier
            record.updatedAt = Date()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            sessions[sessionID] = nil
            try? FileManager.default.removeItem(at: tempDirectory)
            throw error
        }

        let detach = arguments["detach"]?.boolCoerced() ?? false
        if detach {
            return snapshot(for: record)
        }
        let timeout = timeoutSeconds(arguments["timeout"], defaultValue: 120)
        return await waitForSession(sessionID: sessionID, timeoutSeconds: timeout)
    }

    private func pollRun(arguments: [String: MCP.Value]) throws -> HeadlessAgentRunSnapshot {
        let sessionID = try requireNonEmptyString(arguments["session_id"], name: "session_id")
        guard let record = sessions[sessionID] else {
            return expiredSnapshot(sessionID: sessionID)
        }
        return snapshot(for: record)
    }

    private func waitRun(arguments: [String: MCP.Value]) async throws -> HeadlessAgentRunSnapshot {
        let sessionID = try requireNonEmptyString(arguments["session_id"], name: "session_id")
        let timeout = timeoutSeconds(arguments["timeout"], defaultValue: 120)
        return await waitForSession(sessionID: sessionID, timeoutSeconds: timeout)
    }

    private func cancelRun(arguments: [String: MCP.Value]) async throws -> HeadlessAgentRunSnapshot {
        let sessionID = try requireNonEmptyString(arguments["session_id"], name: "session_id")
        guard let record = sessions[sessionID] else { return expiredSnapshot(sessionID: sessionID) }
        guard !record.status.isTerminal else {
            throw HeadlessToolFailure(message: "Headless agent session '\(sessionID)' is already \(record.status.rawValue).")
        }
        record.cancellationRequested = true
        record.status = .cancelled
        record.updatedAt = Date()
        terminate(record.process)
        return snapshot(for: record)
    }

    private func listAgents() throws -> HeadlessAgentListAgentsReply {
        let definitions = try AgentLauncher.definitions(configPath: configuration.agentConfigPath)
        let agents = definitions.keys.sorted().map { name in
            HeadlessAgentInfo(
                name: name,
                available: true,
                models: [HeadlessAgentModelInfo(modelID: name, name: name)]
            )
        }
        return HeadlessAgentListAgentsReply(agents: agents)
    }

    private func listSessions(arguments: [String: MCP.Value]) -> HeadlessAgentListSessionsReply {
        let stateFilter = arguments["state"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let limit = max(0, arguments["limit"]?.intCoerced() ?? 50)
        var summaries = sessions.values
            .filter { record in stateFilter == nil || record.status.rawValue == stateFilter }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(summary(for:))
        if summaries.count > limit {
            summaries = Array(summaries.prefix(limit))
        }
        return HeadlessAgentListSessionsReply(sessions: summaries)
    }

    private func getLog(arguments: [String: MCP.Value]) throws -> HeadlessAgentLogReply {
        let sessionID = try requireNonEmptyString(arguments["session_id"], name: "session_id")
        guard let record = sessions[sessionID] else {
            throw HeadlessToolFailure(message: "Unknown headless agent session '\(sessionID)'.")
        }
        let offset = max(0, arguments["offset"]?.intCoerced() ?? 0)
        let limit = max(0, arguments["limit"]?.intCoerced() ?? 20)
        let includeTurn = offset == 0 && limit > 0
        return HeadlessAgentLogReply(
            sessionID: sessionID,
            name: record.name,
            turnOffset: offset,
            turnLimit: limit,
            returnedTurnCount: includeTurn ? 1 : 0,
            totalTurns: 1,
            transcriptXML: includeTurn ? transcriptXML(for: record) : ""
        )
    }

    private func stopSession(arguments: [String: MCP.Value]) async throws -> HeadlessAgentStopSessionReply {
        let sessionID = try requireNonEmptyString(arguments["session_id"], name: "session_id")
        guard let record = sessions[sessionID] else {
            throw HeadlessToolFailure(message: "Unknown headless agent session '\(sessionID)'.")
        }
        if !record.status.isTerminal {
            record.cancellationRequested = true
            record.status = .cancelled
            record.updatedAt = Date()
            terminate(record.process)
        }
        return HeadlessAgentStopSessionReply(stopRequested: true, session: summary(for: record))
    }

    private func cleanupSessions(arguments: [String: MCP.Value]) throws -> HeadlessAgentCleanupReply {
        guard let sessionIDs = arguments["session_ids"]?.stringArray?.nonEmptyTrimmed(), !sessionIDs.isEmpty else {
            throw HeadlessToolFailure(message: "session_ids must contain at least one session id for cleanup_sessions.")
        }

        var deleted: [HeadlessAgentCleanupReply.CleanupSession] = []
        var skipped: [HeadlessAgentCleanupReply.CleanupSession] = []
        for sessionID in sessionIDs {
            guard let record = sessions[sessionID] else {
                skipped.append(.init(sessionID: sessionID, reason: "not_found"))
                continue
            }
            guard record.status.isTerminal else {
                skipped.append(.init(sessionID: sessionID, reason: "skipped_active"))
                continue
            }
            record.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            record.stderrPipe.fileHandleForReading.readabilityHandler = nil
            sessions[sessionID] = nil
            try? FileManager.default.removeItem(at: record.tempDirectory)
            deleted.append(.init(sessionID: sessionID, reason: nil))
        }
        return HeadlessAgentCleanupReply(
            status: skipped.isEmpty ? "completed" : "partial",
            deletedCount: deleted.count,
            skippedCount: skipped.count,
            deletedSessions: deleted,
            skippedSessions: skipped
        )
    }

    private func waitForSession(sessionID: String, timeoutSeconds: Int) async -> HeadlessAgentRunSnapshot {
        if timeoutSeconds <= 0 {
            guard let record = sessions[sessionID] else { return expiredSnapshot(sessionID: sessionID) }
            return snapshot(for: record)
        }
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while true {
            guard let record = sessions[sessionID] else { return expiredSnapshot(sessionID: sessionID) }
            if record.status.isTerminal { return snapshot(for: record) }
            if Date() >= deadline { return snapshot(for: record, waitResult: "timed_out") }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func appendOutput(sessionID: String, stream: OutputStreamKind, data: Data) {
        guard let record = sessions[sessionID] else { return }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        switch stream {
        case .stdout:
            append(text, to: &record.stdout, truncated: &record.stdoutTruncated)
        case .stderr:
            append(text, to: &record.stderr, truncated: &record.stderrTruncated)
        }
        record.updatedAt = Date()
    }

    private func completeSession(sessionID: String, exitCode: Int32) {
        guard let record = sessions[sessionID] else { return }
        drainPipe(record.stdoutPipe, sessionID: sessionID, stream: .stdout)
        drainPipe(record.stderrPipe, sessionID: sessionID, stream: .stderr)
        record.stdoutPipe.fileHandleForReading.readabilityHandler = nil
        record.stderrPipe.fileHandleForReading.readabilityHandler = nil
        record.exitCode = exitCode
        if record.status == .running {
            record.status = exitCode == 0 ? .completed : .failed
        }
        record.updatedAt = Date()
    }

    private func drainPipe(_ pipe: Pipe, sessionID: String, stream: OutputStreamKind) {
        let data = pipe.fileHandleForReading.availableData
        guard !data.isEmpty else { return }
        appendOutput(sessionID: sessionID, stream: stream, data: data)
    }

    private func append(_ text: String, to output: inout String, truncated: inout Bool) {
        guard !text.isEmpty, configuration.outputCaptureLimitBytes > 0 else { return }
        let existing = output.data(using: .utf8)?.count ?? output.utf8.count
        let incoming = text.data(using: .utf8)?.count ?? text.utf8.count
        let allowed = configuration.outputCaptureLimitBytes - existing
        if allowed <= 0 {
            truncated = true
            return
        }
        if incoming <= allowed {
            output += text
            return
        }
        let prefix = text.prefix(allowed)
        output += String(prefix)
        truncated = true
    }

    private func ensureSocketServer() throws -> String {
        if let listener, let socketPath {
            _ = listener
            return socketPath
        }
        let directory = configuration.socketDirectory
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let path = if let directory {
            directory.appendingPathComponent("agent-\(getpid()).sock").path
        } else {
            "/tmp/rpce-ha-\(getpid())-\(UUID().uuidString.prefix(8)).sock"
        }
        let newListener = HeadlessUnixSocketListener(path: path)
        try newListener.start { [host] fd in
            do {
                try await HeadlessMCPServer(host: host).runSocketConnection(fd: fd)
            } catch {
                fputs("rpce-headless agent socket connection: \(error.localizedDescription)\n", stderr)
            }
        }
        listener = newListener
        socketPath = path
        if configuration.socketDirectory == nil {
            socketTempDirectory = directory
        }
        return path
    }

    private func snapshot(for record: SessionRecord, waitResult: String? = nil) -> HeadlessAgentRunSnapshot {
        HeadlessAgentRunSnapshot(
            sessionID: record.id,
            status: record.status.rawValue,
            statusText: statusText(for: record),
            assistantText: assistantText(for: record),
            transcriptItemCount: 1,
            updatedAt: timestamp(record.updatedAt),
            session: .init(id: record.id, name: record.name),
            agent: .init(id: "headless", name: record.agentName, model: record.modelID, reasoningEffort: nil),
            meta: waitResult.map { .init(waitResult: $0) }
        )
    }

    private func expiredSnapshot(sessionID: String) -> HeadlessAgentRunSnapshot {
        let now = Date()
        return HeadlessAgentRunSnapshot(
            sessionID: sessionID,
            status: HeadlessAgentRunStatus.expired.rawValue,
            statusText: "Headless agent session is unavailable or expired.",
            assistantText: "",
            transcriptItemCount: 0,
            updatedAt: timestamp(now),
            session: .init(id: sessionID, name: "Expired headless agent session"),
            agent: .init(id: "headless", name: "unknown", model: "unknown", reasoningEffort: nil),
            meta: nil
        )
    }

    private func summary(for record: SessionRecord) -> HeadlessAgentSessionSummary {
        HeadlessAgentSessionSummary(
            sessionID: record.id,
            name: record.name,
            lastModified: timestamp(record.updatedAt),
            itemCount: 1,
            state: record.status.rawValue,
            isLive: record.status == .running,
            agent: .init(id: "headless", model: record.modelID),
            isMCPOriginated: true
        )
    }

    private func statusText(for record: SessionRecord) -> String {
        switch record.status {
        case .running:
            "Headless agent process is running."
        case .completed:
            "Headless agent process completed with exit code \(record.exitCode ?? 0)."
        case .failed:
            "Headless agent process failed with exit code \(record.exitCode ?? -1)."
        case .cancelled:
            "Headless agent process was cancelled."
        case .expired:
            "Headless agent session is unavailable or expired."
        }
    }

    private func assistantText(for record: SessionRecord) -> String {
        var parts: [String] = []
        if !record.stdout.isEmpty { parts.append(record.stdout) }
        if !record.stderr.isEmpty { parts.append(record.stderr) }
        return parts.joined(separator: "\n")
    }

    private func transcriptXML(for record: SessionRecord) -> String {
        """
        <headless_agent_session id=\"\(xmlEscape(record.id))\" name=\"\(xmlEscape(record.name))\" status=\"\(record.status.rawValue)\">
          <agent name=\"\(xmlEscape(record.agentName))\" model=\"\(xmlEscape(record.modelID))\" />
          <started_at>\(xmlEscape(timestamp(record.startedAt)))</started_at>
          <updated_at>\(xmlEscape(timestamp(record.updatedAt)))</updated_at>
          <exit_code>\(record.exitCode.map(String.init) ?? "")</exit_code>
          <prompt>\(xmlEscape(record.prompt))</prompt>
          <stdout truncated=\"\(record.stdoutTruncated)\">\(xmlEscape(record.stdout))</stdout>
          <stderr truncated=\"\(record.stderrTruncated)\">\(xmlEscape(record.stderr))</stderr>
        </headless_agent_session>
        """
    }

    private func rejectUnsupportedStartArguments(_ arguments: [String: MCP.Value]) throws {
        let unsupported = [
            "workflow_name", "workflow_id", "worktree", "worktree_id", "worktree_create",
            "worktree_repo_root", "worktree_branch", "session_id", "interaction_id", "answers",
            "messages", "steer", "respond"
        ]
        if let key = unsupported.first(where: { arguments[$0] != nil }) {
            throw HeadlessToolFailure(message: "\(key) is not supported by headless process-backed agent_run.start.")
        }
    }

    private func requireNonEmptyString(_ value: MCP.Value?, name: String) throws -> String {
        guard let raw = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw HeadlessToolFailure(message: "\(name) is required and must be a non-empty string.")
        }
        return raw
    }

    private func timeoutSeconds(_ value: MCP.Value?, defaultValue: Int) -> Int {
        max(0, value?.intCoerced() ?? defaultValue)
    }

    private func timestamp(_ date: Date) -> String {
        DateFormatter.headlessAgentISO8601.string(from: date)
    }

    private func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func jsonTextResult(_ value: some Codable) throws -> CallTool.Result {
        try CallTool.Result(
            content: [.text(text: HeadlessJSON.string(value), annotations: nil, _meta: nil)],
            structuredContent: value,
            isError: false
        )
    }

    private func terminate(_ process: Process) {
        #if canImport(Darwin) || canImport(Glibc)
            if process.processIdentifier > 0 {
                kill(-process.processIdentifier, SIGTERM)
            }
        #endif
        process.terminate()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning {
                #if canImport(Darwin) || canImport(Glibc)
                    if process.processIdentifier > 0 {
                        kill(-process.processIdentifier, SIGKILL)
                        kill(process.processIdentifier, SIGKILL)
                    }
                #endif
            }
        }
    }

    private func setProcessGroup(for process: Process) {
        #if canImport(Darwin) || canImport(Glibc)
            setpgid(process.processIdentifier, process.processIdentifier)
        #endif
    }
}

private func currentHeadlessExecutablePath() throws -> String {
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
