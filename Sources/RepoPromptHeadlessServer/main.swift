import Foundation

do {
    let command = try HeadlessCLI.parse(Array(CommandLine.arguments.dropFirst()))
    switch command {
    case let .serve(roots, socketPath):
        let host = try await HeadlessWorkspaceHost(rootPaths: roots)
        let server = HeadlessMCPServer(host: host)
        if let socketPath {
            let listener = HeadlessUnixSocketListener(path: socketPath)
            try listener.start { fd in
                do {
                    try await HeadlessMCPServer(host: host).runSocketConnection(fd: fd)
                } catch {
                    fputs("rpce-headless socket connection: \(error.localizedDescription)\n", stderr)
                }
            }
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(3600))
            }
        } else {
            try await server.run()
        }
    case let .dump(roots):
        let host = try await HeadlessWorkspaceHost(rootPaths: roots)
        let summary = await host.dumpSummary()
        print(summary)
    case let .connect(socketPath):
        try await ConnectBridge.run(socketPath: socketPath)
    case let .contextBuild(options):
        let exitCode = try await ContextBuildCommand(options: options).run()
        Foundation.exit(exitCode)
    }
} catch let error as HeadlessCLI.ExitError {
    fputs(error.message + "\n", stderr)
    Foundation.exit(error.code)
} catch {
    fputs("rpce-headless: \(error.localizedDescription)\n", stderr)
    Foundation.exit(1)
}

enum HeadlessCLI {
    enum Command {
        case serve(roots: [String], socketPath: String?)
        case dump(roots: [String])
        case connect(socketPath: String)
        case contextBuild(ContextBuildOptions)
    }

    struct ExitError: Error {
        let code: Int32
        let message: String
    }

    static func parse(_ args: [String]) throws -> Command {
        guard let subcommand = args.first else { throw usage() }
        guard ["serve", "dump", "connect", "context-build"].contains(subcommand) else { throw usage() }

        if subcommand == "connect" {
            var socketPath: String?
            var index = 1
            while index < args.count {
                switch args[index] {
                case "--socket":
                    let valueIndex = index + 1
                    guard valueIndex < args.count else { throw usage("--socket requires a path") }
                    socketPath = args[valueIndex]
                    index += 2
                default:
                    throw usage("Unknown argument: \(args[index])")
                }
            }
            guard let socketPath else { throw usage("connect requires --socket <path>") }
            return .connect(socketPath: socketPath)
        }

        if subcommand == "context-build" {
            return try .contextBuild(parseContextBuild(Array(args.dropFirst())))
        }

        var roots: [String] = []
        var socketPath: String?
        var index = 1
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--root":
                let valueIndex = index + 1
                guard valueIndex < args.count else { throw usage("--root requires a path") }
                try roots.append(resolveRoot(args[valueIndex]))
                index += 2
            case "--socket":
                let valueIndex = index + 1
                guard subcommand == "serve" else { throw usage("--socket is only valid for serve") }
                guard valueIndex < args.count else { throw usage("--socket requires a path") }
                socketPath = args[valueIndex]
                index += 2
            default:
                throw usage("Unknown argument: \(arg)")
            }
        }
        guard !roots.isEmpty else { throw usage("At least one --root is required") }
        return subcommand == "serve" ? .serve(roots: roots, socketPath: socketPath) : .dump(roots: roots)
    }

    private static func parseContextBuild(_ args: [String]) throws -> ContextBuildOptions {
        var roots: [String] = []
        var instructions: String?
        var agent = "fake"
        var configPath: String?
        var socketPath: String?
        var tokenBudget = 118_500
        var responseType = ContextBuildResponseType.selection
        var timeoutSeconds = 900
        var dryRun = false

        var index = 0
        while index < args.count {
            switch args[index] {
            case "--root":
                let valueIndex = index + 1
                guard valueIndex < args.count else { throw usage("--root requires a path") }
                try roots.append(resolveRoot(args[valueIndex]))
                index += 2
            case "--instructions":
                let valueIndex = index + 1
                guard valueIndex < args.count else { throw usage("--instructions requires text") }
                instructions = args[valueIndex]
                index += 2
            case "--agent":
                let valueIndex = index + 1
                guard valueIndex < args.count else { throw usage("--agent requires a name") }
                agent = args[valueIndex]
                index += 2
            case "--agent-config":
                let valueIndex = index + 1
                guard valueIndex < args.count else { throw usage("--agent-config requires a path") }
                configPath = args[valueIndex]
                index += 2
            case "--socket":
                let valueIndex = index + 1
                guard valueIndex < args.count else { throw usage("--socket requires a path") }
                socketPath = args[valueIndex]
                index += 2
            case "--token-budget":
                let valueIndex = index + 1
                guard valueIndex < args.count, let value = Int(args[valueIndex]) else { throw usage("--token-budget requires an integer") }
                tokenBudget = value
                index += 2
            case "--response-type":
                let valueIndex = index + 1
                guard valueIndex < args.count, let value = ContextBuildResponseType(rawValue: args[valueIndex]) else {
                    throw usage("--response-type must be selection, question, plan, or review")
                }
                responseType = value
                index += 2
            case "--timeout":
                let valueIndex = index + 1
                guard valueIndex < args.count, let value = Int(args[valueIndex]) else { throw usage("--timeout requires seconds") }
                timeoutSeconds = value
                index += 2
            case "--dry-run":
                dryRun = true
                index += 1
            default:
                throw usage("Unknown argument: \(args[index])")
            }
        }
        guard !roots.isEmpty else { throw usage("context-build requires at least one --root") }
        guard let instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw usage("context-build requires --instructions <text>")
        }
        return ContextBuildOptions(
            roots: roots,
            instructions: instructions,
            agentName: agent,
            agentConfigPath: configPath,
            socketPath: socketPath,
            tokenBudget: tokenBudget,
            responseType: responseType,
            timeoutSeconds: timeoutSeconds,
            dryRun: dryRun
        )
    }

    private static func resolveRoot(_ path: String) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let absolute: String = if expanded.hasPrefix("/") {
            expanded
        } else {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expanded).path
        }
        let standardized = (absolute as NSString).standardizingPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExitError(code: 66, message: "Root does not exist or is not a directory: \(standardized)")
        }
        return standardized
    }

    private static func usage(_ detail: String? = nil) -> ExitError {
        var lines: [String] = []
        if let detail { lines.append("Error: \(detail)") }
        lines.append("Usage: rpce-headless serve --root <path> [--root <path> ...] [--socket <path>]")
        lines.append("       rpce-headless connect --socket <path>")
        lines.append("       rpce-headless context-build --root <path> --instructions <text> [--agent <name>] [--dry-run]")
        lines.append("       rpce-headless dump --root <path> [--root <path> ...]")
        return ExitError(code: 64, message: lines.joined(separator: "\n"))
    }
}
