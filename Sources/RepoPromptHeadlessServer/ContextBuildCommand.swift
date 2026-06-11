import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct ContextBuildCommand {
    let options: ContextBuildOptions

    func run() async throws -> Int32 {
        let prompt = DiscoverPromptBuilder.build(
            instructions: options.instructions,
            tokenBudget: options.tokenBudget,
            responseType: options.responseType
        )
        let socketPath = options.socketPath ?? defaultHeadlessSocketPath()
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rpce-headless-context-\(UUID().uuidString)", isDirectory: true)
        let executablePath = try currentExecutablePath()
        let launch = try AgentLauncher.render(
            agentName: options.agentName,
            configPath: options.agentConfigPath,
            prompt: prompt,
            socketPath: socketPath,
            executablePath: executablePath,
            tempDirectory: tempDirectory
        )

        if options.dryRun {
            printDryRun(launch: launch, socketPath: socketPath)
            return 0
        }

        let host = try await HeadlessWorkspaceHost(rootPaths: options.roots)
        let listener = HeadlessUnixSocketListener(path: socketPath)
        try listener.start { fd in
            do {
                try await HeadlessMCPServer(host: host).runSocketConnection(fd: fd)
            } catch {
                fputs("rpce-headless socket connection: \(error.localizedDescription)\n", stderr)
                closeFD(fd)
            }
        }
        defer {
            listener.stop()
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let agentExit = try await runAgent(launch)
        let harvest = try await host.contextBuildHarvest()
        var report = renderReport(agentExit: agentExit, harvest: harvest)

        if options.responseType == .question || options.responseType == .plan {
            let oracle = OracleService(host: host)
            let message = """
            User instructions:
            \(options.instructions)

            Discovery handoff:
            \(harvest.prompt)

            Workspace context:
            \(harvest.context)
            """
            let reply = try await oracle.send(
                message: message,
                chatID: nil,
                model: nil,
                includeContext: false
            )
            var answer = ""
            for try await delta in reply.stream {
                answer += delta
            }
            await oracle.shutdown()
            report += "\nanswer:\n\(answer)\n"
        }

        print(report, terminator: report.hasSuffix("\n") ? "" : "\n")
        if agentExit != 0 { return agentExit }
        if harvest.selectedFiles.isEmpty { return 2 }
        return 0
    }

    private func runAgent(_ launch: RenderedAgentLaunch) async throws -> Int32 {
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
            try? await Task.sleep(for: .seconds(max(1, options.timeoutSeconds)))
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

    private func renderReport(agentExit: Int32, harvest: HeadlessContextBuildHarvest) -> String {
        var lines: [String] = []
        lines.append("== context-build report ==")
        lines.append("agent exit: \(agentExit)")
        lines.append("selection (\(harvest.selectedFiles.count) files, ~\(harvest.totalTokens) tokens):")
        if harvest.selectedFiles.isEmpty {
            lines.append("  <empty>")
        } else {
            for file in harvest.selectedFiles {
                lines.append("  \(file.path)  \(file.tokens)")
            }
        }
        if !harvest.codemapFiles.isEmpty {
            lines.append("codemaps (\(harvest.codemapFiles.count) files):")
            for path in harvest.codemapFiles {
                lines.append("  \(path)")
            }
        }
        lines.append("prompt:")
        lines.append(harvest.prompt)
        return lines.joined(separator: "\n")
    }

    private func printDryRun(launch: RenderedAgentLaunch, socketPath: String) {
        print("== context-build dry-run ==")
        print("socket: \(socketPath)")
        print("prompt_file: \(launch.promptPath)")
        print("mcp_config: \(launch.mcpConfigPath)")
        print("argv:")
        for arg in launch.argv {
            print("  \(arg)")
        }
        print("prompt:")
        print(launch.prompt)
    }

    private func currentExecutablePath() throws -> String {
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
