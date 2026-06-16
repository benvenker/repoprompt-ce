import Foundation

do {
    let command = try HeadlessCLI.parse(Array(CommandLine.arguments.dropFirst()))
    switch command {
    case let .help(text):
        print(text)
    case let .serve(roots, socketPath, exposeAllTools):
        let host = try await HeadlessWorkspaceHost(rootPaths: roots)
        let server = HeadlessMCPServer(host: host)
        if let socketPath {
            let socketAccess = try HeadlessSocketAccess(exposeAllTools: exposeAllTools)
            let listener = HeadlessUnixSocketListener(path: socketPath)
            try listener.start { fd in
                do {
                    switch socketAccess {
                    case .restricted:
                        try await HeadlessMCPServer(host: host).runSocketConnection(fd: fd)
                    case let .fullTools(authToken):
                        try await HeadlessMCPServer(host: host).runFullAccessSocketConnection(fd: fd, expectedToken: authToken)
                    }
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
    case let .dump(roots, json):
        let host = try await HeadlessWorkspaceHost(rootPaths: roots)
        if json {
            let summary = await host.dumpSummaryReply()
            print(try HeadlessJSON.string(summary))
        } else {
            let summary = await host.dumpSummary()
            print(summary)
        }
    case let .connect(socketPath, auth):
        try await ConnectBridge.run(socketPath: socketPath, auth: auth)
    case let .contextBuild(options):
        let exitCode = try await ContextBuildCommand(options: options).run()
        Foundation.exit(exitCode)
    case .capabilities:
        let root = (FileManager.default.currentDirectoryPath as NSString).standardizingPath
        print(try HeadlessJSON.string(HeadlessCapabilities.make(loadedRoots: [root])))
    case .robotDocsGuide:
        print(HeadlessCapabilities.robotDocsGuide())
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
        case help(String)
        case serve(roots: [String], socketPath: String?, exposeAllTools: Bool)
        case dump(roots: [String], json: Bool)
        case connect(socketPath: String, auth: Bool)
        case contextBuild(ContextBuildOptions)
        case capabilities
        case robotDocsGuide
    }

    struct ExitError: Error, LocalizedError {
        let code: Int32
        let message: String

        var errorDescription: String? {
            message
        }
    }

    static func parse(_ args: [String]) throws -> Command {
        guard let subcommand = args.first else { return .help(topLevelHelp) }
        if ["--help", "-h", "help"].contains(subcommand) { return .help(topLevelHelp) }
        let knownSubcommands = ["serve", "dump", "connect", "context-build", "capabilities", "robot-docs"]
        guard knownSubcommands.contains(subcommand) else {
            throw usage("Unknown subcommand: \(subcommand). Run `rpce-headless --help`.")
        }

        if args.dropFirst().contains("--help") || args.dropFirst().contains("-h") {
            return .help(help(for: subcommand))
        }

        if subcommand == "capabilities" {
            for arg in args.dropFirst() {
                guard arg == "--json" else { throw usage(unknownArgumentMessage(arg, valid: ["--json"])) }
            }
            return .capabilities
        }

        if subcommand == "robot-docs" {
            let tail = Array(args.dropFirst())
            if tail.isEmpty || tail == ["guide"] {
                return .robotDocsGuide
            }
            throw usage("Unknown robot-docs topic: \(tail.joined(separator: " ")). Use `rpce-headless robot-docs guide`.")
        }

        if subcommand == "connect" {
            var socketPath: String?
            var auth = false
            var index = 1
            while index < args.count {
                switch args[index] {
                case "--socket":
                    let valueIndex = index + 1
                    guard valueIndex < args.count else { throw usage("--socket requires a path") }
                    socketPath = args[valueIndex]
                    index += 2
                case "--auth":
                    auth = true
                    index += 1
                default:
                    throw usage(unknownArgumentMessage(args[index], valid: ["--socket", "--auth"]))
                }
            }
            guard let socketPath else { throw usage("connect requires --socket <path>") }
            return .connect(socketPath: socketPath, auth: auth)
        }

        if subcommand == "context-build" {
            return try .contextBuild(parseContextBuild(Array(args.dropFirst())))
        }

        var roots: [String] = []
        var socketPath: String?
        var exposeAllTools = false
        var json = false
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
            case "--expose-all-tools":
                guard subcommand == "serve" else { throw usage("--expose-all-tools is only valid for serve") }
                exposeAllTools = true
                index += 1
            case "--json":
                guard subcommand == "dump" else { throw usage("--json is only valid for dump and capabilities") }
                json = true
                index += 1
            default:
                let valid = subcommand == "serve"
                    ? ["--root", "--socket", "--expose-all-tools"]
                    : ["--root", "--json"]
                throw usage(unknownArgumentMessage(arg, valid: valid))
            }
        }
        if roots.isEmpty {
            try roots.append(defaultRoot())
        }
        guard !exposeAllTools || socketPath != nil else { throw usage("--expose-all-tools requires --socket") }
        return subcommand == "serve" ? .serve(roots: roots, socketPath: socketPath, exposeAllTools: exposeAllTools) : .dump(roots: roots, json: json)
    }

    private static func parseContextBuild(_ args: [String]) throws -> ContextBuildOptions {
        var roots: [String] = []
        var instructions: String?
        var agent = "claude"
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
                throw usage(unknownArgumentMessage(args[index], valid: ["--root", "--instructions", "--agent", "--agent-config", "--socket", "--token-budget", "--response-type", "--timeout", "--dry-run"]))
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

    static func defaultRoot() throws -> String {
        try resolveRoot(FileManager.default.currentDirectoryPath)
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
        lines.append(topLevelHelp)
        return ExitError(code: 64, message: lines.joined(separator: "\n"))
    }

    private static func help(for subcommand: String) -> String {
        switch subcommand {
        case "serve":
            """
            Usage: rpce-headless serve [--root <path> ...] [--socket <path> [--expose-all-tools]]

            Start an MCP server. If --root is omitted, the current working directory is loaded.
            Stdio mode exposes all tools. Socket mode is discovery-restricted unless --expose-all-tools is used with RPCE_SOCKET_AUTH_TOKEN.
            """
        case "dump":
            """
            Usage: rpce-headless dump [--root <path> ...] [--json]

            Print a catalog summary for the loaded roots. If --root is omitted, the current working directory is loaded.
            Use --json for a stable machine-readable payload including loaded_roots.
            """
        case "connect":
            """
            Usage: rpce-headless connect --socket <path> [--auth]

            Bridge stdin/stdout JSON-RPC to a Unix socket. --auth reads RPCE_SOCKET_AUTH_TOKEN and sends it before JSON-RPC.
            """
        case "context-build":
            """
            Usage: rpce-headless context-build --root <path> --instructions <text> [options]

            Options:
              --agent <name>             Configured discovery agent name.
              --agent-config <path>      Agent template JSON; defaults to ~/.config/rpce-headless/agents.json.
              --socket <path>            Unix socket path for the temporary restricted server.
              --token-budget <tokens>    Selection token budget.
              --response-type <type>     selection, question, plan, or review.
              --timeout <seconds>        Discovery-agent lifetime cap.
              --dry-run                  Render the generated prompt/config without spawning the agent.

            Launch a configured discovery agent against a restricted local socket, then harvest selected context.
            Use response types selection, question, plan, or review. question/plan/review require oracle credentials.
            """
        case "capabilities":
            """
            Usage: rpce-headless capabilities --json

            Print the agent-readable rpce-headless contract: version, exit codes, root semantics, tool exposure, recommended workflow, environment, and smoke commands.
            """
        case "robot-docs":
            """
            Usage: rpce-headless robot-docs guide

            Print a paste-ready agent handbook for onboarding to rpce-headless.
            """
        default:
            topLevelHelp
        }
    }

    private static let topLevelHelp = """
    Usage: rpce-headless <command> [options]

    Commands:
      serve          Start the MCP server; omit --root to load the current directory.
      dump           Print a loaded-workspace catalog summary; supports --json.
      connect        Bridge stdio JSON-RPC to a Unix socket.
      context-build  Run the headless Context Builder orchestration.
      capabilities   Print the machine-readable agent contract; use --json.
      robot-docs     Print the agent onboarding guide; use `robot-docs guide`.

    First commands for agents:
      rpce-headless capabilities --json
      rpce-headless robot-docs guide
      rpce-headless dump --json
      rpce-headless serve

    Exit codes:
      0 success
      64 command-line usage error
      65 socket authentication rejected
      66 requested root does not exist or is not a directory
      69 runtime environment error
    """

    private static func unknownArgumentMessage(_ argument: String, valid: [String]) -> String {
        if let suggestion = suggestion(for: argument, valid: valid) {
            return "Unknown argument: \(argument). Did you mean `\(suggestion)`?"
        }
        return "Unknown argument: \(argument). Valid arguments: \(valid.joined(separator: ", "))"
    }

    private static func suggestion(for argument: String, valid: [String]) -> String? {
        let aliases = [
            "--jsno": "--json",
            "--jason": "--json",
            "--colour": "--color",
            "--licence": "--license"
        ]
        if let alias = aliases[argument], valid.contains(alias) { return alias }
        return valid.first { levenshteinDistance(argument, $0) <= 2 }
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        var previous = Array(0...right.count)
        for (leftIndex, leftChar) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightChar) in right.enumerated() {
                if leftChar == rightChar {
                    current.append(previous[rightIndex])
                } else {
                    current.append(min(previous[rightIndex], previous[rightIndex + 1], current[rightIndex]) + 1)
                }
            }
            previous = current
        }
        return previous[right.count]
    }
}

private enum HeadlessSocketAccess {
    case restricted
    case fullTools(authToken: String)

    init(exposeAllTools: Bool) throws {
        guard exposeAllTools else {
            self = .restricted
            return
        }

        let token = ProcessInfo.processInfo.environment["RPCE_SOCKET_AUTH_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, token.count >= 16 else {
            throw HeadlessCLI.ExitError(
                code: 64,
                message: "--expose-all-tools requires RPCE_SOCKET_AUTH_TOKEN (at least 16 characters) in the environment"
            )
        }
        self = .fullTools(authToken: token)
    }
}
