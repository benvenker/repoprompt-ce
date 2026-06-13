import Foundation

struct ContextBuildCommand {
    let options: ContextBuildOptions

    func run() async throws -> Int32 {
        let request = HeadlessContextBuilderRequest(
            instructions: options.instructions,
            agentName: options.agentName,
            agentConfigPath: options.agentConfigPath,
            socketPath: options.socketPath,
            tokenBudget: options.tokenBudget,
            responseType: options.responseType,
            responseTypeName: options.responseType.rawValue,
            timeoutSeconds: options.timeoutSeconds,
            exportResponse: false
        )
        let prepared = try HeadlessContextBuilderService.prepareLaunch(request: request)

        if options.dryRun {
            printDryRun(launch: prepared.launch, socketPath: prepared.socketPath)
            try? FileManager.default.removeItem(at: prepared.tempDirectory)
            return 0
        }

        let host = try await HeadlessWorkspaceHost(rootPaths: options.roots)
        let oracle = OracleService(host: host)
        let service = HeadlessContextBuilderService(host: host)
        let execution: HeadlessContextBuilderExecution
        do {
            execution = try await service.run(request: request, oracleService: oracle)
        } catch {
            await oracle.shutdown()
            throw error
        }
        await oracle.shutdown()

        var report = renderReport(agentExit: execution.agentExit, harvest: execution.harvest)
        if let answer = execution.answer {
            report += "\nanswer:\n\(answer)\n"
        }

        print(report, terminator: report.hasSuffix("\n") ? "" : "\n")
        if execution.agentExit != 0 { return execution.agentExit }
        if execution.harvest.selectedFiles.isEmpty { return 2 }
        return 0
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
}
