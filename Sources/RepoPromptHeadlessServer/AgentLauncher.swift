import Foundation

enum ContextBuildResponseType: String {
    case selection
    case question
    case plan
    case review
}

struct ContextBuildOptions {
    let roots: [String]
    let instructions: String
    let agentName: String
    let agentConfigPath: String?
    let socketPath: String?
    let tokenBudget: Int
    let responseType: ContextBuildResponseType
    let timeoutSeconds: Int
    let dryRun: Bool
}

struct AgentDefinition: Codable {
    let argv: [String]
    let promptVia: String?
}

struct AgentDefinitionAvailability {
    let definition: AgentDefinition
    let available: Bool
    let unavailableReason: String?
}

struct RenderedAgentLaunch {
    let argv: [String]
    let environment: [String: String]
    let mcpConfigPath: String
    let promptPath: String
    let prompt: String
}

enum AgentLauncher {
    static func render(
        agentName: String,
        configPath: String?,
        prompt: String,
        socketPath: String,
        executablePath: String,
        tempDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RenderedAgentLaunch {
        let definitions = try definitions(configPath: configPath, environment: environment)
        guard let definition = definitions[agentName] else {
            throw HeadlessCLI.ExitError(code: 64, message: "Unknown agent '\(agentName)'. Available agents: \(definitions.keys.sorted().joined(separator: ", "))")
        }
        if let reason = unavailableReason(for: definition, environment: environment) {
            throw HeadlessCLI.ExitError(code: 64, message: "Agent '\(agentName)' is unavailable: \(reason)")
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let promptPath = tempDirectory.appendingPathComponent("discover-prompt.txt")
        try prompt.write(to: promptPath, atomically: true, encoding: .utf8)

        let mcpConfigPath = tempDirectory.appendingPathComponent("mcp-config.json")
        let mcpConfig = MCPConfig(mcpServers: [
            "repoprompt": MCPServerConfig(command: executablePath, args: ["connect", "--socket", socketPath])
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(mcpConfig).write(to: mcpConfigPath, options: [.atomic])

        var substitutions = [
            "PROMPT": prompt,
            "PROMPT_FILE": promptPath.path,
            "MCP_CONFIG": mcpConfigPath.path,
            "MCP_CONFIG_PATH_RAW": mcpConfigPath.path
        ]
        if let fakeAgent = environment["FAKE_AGENT_SCRIPT"], !fakeAgent.isEmpty {
            substitutions["FAKE_AGENT_SCRIPT"] = fakeAgent
        }

        let renderedArgv = try definition.argv.map { argument in
            try replacePlaceholders(argument, substitutions: substitutions)
        }
        guard !renderedArgv.isEmpty else {
            throw HeadlessCLI.ExitError(code: 64, message: "Agent '\(agentName)' has an empty argv")
        }

        var launchEnvironment = environment
        launchEnvironment["RPCE_DISCOVER_PROMPT"] = prompt
        launchEnvironment["RPCE_MCP_CONFIG"] = mcpConfigPath.path
        launchEnvironment["RPCE_SOCKET_PATH"] = socketPath
        launchEnvironment["RPCE_PROMPT_FILE"] = promptPath.path

        return RenderedAgentLaunch(
            argv: renderedArgv,
            environment: launchEnvironment,
            mcpConfigPath: mcpConfigPath.path,
            promptPath: promptPath.path,
            prompt: prompt
        )
    }

    static func definitions(
        configPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [String: AgentDefinition] {
        if let configPath {
            let expanded = (configPath as NSString).expandingTildeInPath
            let data = try Data(contentsOf: URL(fileURLWithPath: expanded))
            return try JSONDecoder().decode([String: AgentDefinition].self, from: data)
        }

        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/rpce-headless/agents.json")
        if FileManager.default.fileExists(atPath: defaultPath.path) {
            let data = try Data(contentsOf: defaultPath)
            return try JSONDecoder().decode([String: AgentDefinition].self, from: data)
        }

        var definitions = [
            "claude": AgentDefinition(
                argv: ["claude", "-p", "{PROMPT}", "--mcp-config", "{MCP_CONFIG}", "--strict-mcp-config", "--permission-mode", "bypassPermissions"],
                promptVia: "argv"
            )
        ]
        if environment.headlessTrimmed("FAKE_AGENT_SCRIPT") != nil {
            definitions["fake"] = AgentDefinition(
                argv: ["python3", "{FAKE_AGENT_SCRIPT}", "{MCP_CONFIG_PATH_RAW}"],
                promptVia: "env"
            )
        }
        return definitions
    }

    static func definitionAvailability(
        configPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [String: AgentDefinitionAvailability] {
        let definitions = try definitions(configPath: configPath, environment: environment)
        return definitions.mapValues { definition in
            let reason = unavailableReason(for: definition, environment: environment)
            return AgentDefinitionAvailability(
                definition: definition,
                available: reason == nil,
                unavailableReason: reason
            )
        }
    }

    private static func replacePlaceholders(_ text: String, substitutions: [String: String]) throws -> String {
        var rendered = text
        for (name, value) in substitutions {
            rendered = rendered.replacingOccurrences(of: "{\(name)}", with: value)
        }
        let knownPlaceholders = ["PROMPT", "PROMPT_FILE", "MCP_CONFIG", "MCP_CONFIG_PATH_RAW", "FAKE_AGENT_SCRIPT"]
        for name in knownPlaceholders where rendered.contains("{\(name)}") {
            throw HeadlessCLI.ExitError(code: 64, message: "Missing value for agent placeholder {\(name)}")
        }
        return rendered
    }

    private static func unavailableReason(
        for definition: AgentDefinition,
        environment: [String: String]
    ) -> String? {
        let needsFakeAgent = definition.argv.contains { $0.contains("{FAKE_AGENT_SCRIPT}") }
        guard needsFakeAgent, environment.headlessTrimmed("FAKE_AGENT_SCRIPT") == nil else { return nil }
        return "missing value for agent placeholder {FAKE_AGENT_SCRIPT}; the fake agent is a smoke-test fixture and requires FAKE_AGENT_SCRIPT"
    }
}

private struct MCPConfig: Encodable {
    let mcpServers: [String: MCPServerConfig]
}

private struct MCPServerConfig: Encodable {
    let command: String
    let args: [String]
}
