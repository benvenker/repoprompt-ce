import Foundation
import MCP

enum HeadlessCapabilities {
    static let contractVersion = "1"

    static func make(loadedRoots: [String]) -> HeadlessCapabilitiesReply {
        HeadlessCapabilitiesReply(
            toolName: "rpce-headless",
            serverVersion: HeadlessMCPServer.version,
            contractVersion: contractVersion,
            loadedRoots: loadedRoots,
            rootSemantics: .init(
                defaultBehavior: "serve and dump load the current working directory when --root is omitted",
                globalCodexRecommendation: "Use command=/home/ben/.local/bin/rpce-headless and args=[\"serve\"] so each chat loads its own cwd."
            ),
            transports: [
                .init(
                    name: "stdio",
                    exposure: "full",
                    tools: HeadlessToolSchemas.tools.map(\.name).sorted(),
                    authentication: "client launches the process directly; no MCP-level auth"
                ),
                .init(
                    name: "socket",
                    exposure: "discovery_restricted",
                    tools: HeadlessToolSchemas.discoveryToolNames.sorted(),
                    authentication: "local Unix socket; use --expose-all-tools plus RPCE_SOCKET_AUTH_TOKEN for authenticated full-tool sockets"
                )
            ],
            recommendedWorkflow: [
                "Call headless_capabilities or rpce-headless capabilities --json first.",
                "Verify loaded_roots before exploring.",
                "Use get_file_tree, file_search, read_file, and get_code_structure for direct evidence.",
                "Use context_builder for curated multi-file discovery when the task needs synthesis.",
                "Use agent_manage list_agents before agent_run; choose an available real configured agent, start bounded read-only tasks, wait or poll, get logs, then cleanup_sessions.",
                "Use oracle_send only when explicitly requested or when external inference is appropriate."
            ],
            contextBuilder: .init(
                syncExample: #"{"instructions":"Map this repo","response_type":"clarify"}"#,
                asyncStartExample: #"{"op":"start","instructions":"Map this repo","response_type":"clarify","token_budget":160000,"timeout_seconds":900}"#,
                asyncWaitExample: #"{"op":"wait","context_id":"<context_id>","timeout":30}"#,
                asyncResultExample: #"{"op":"get_result","context_id":"<context_id>"}"#,
                cleanupExample: #"{"op":"cleanup","context_id":"<context_id>"}"#,
                timeoutGuidance: "timeout_seconds caps the spawned discovery-agent lifetime on start/one-shot. timeout is only the client wait deadline for op=wait."
            ),
            agentRun: .init(
                listAgentsExample: #"{"op":"list_agents"}"#,
                startExample: #"{"op":"start","model_id":"claude","message":"Read-only: inspect architecture and report evidence.","detach":true,"timeout":0}"#,
                waitExample: #"{"op":"wait","session_id":"<session_id>","timeout":60}"#,
                logExample: #"{"op":"get_log","session_id":"<session_id>","limit":40}"#,
                cleanupExample: #"{"op":"cleanup_sessions","session_ids":["<session_id>"]}"#,
                fakeAgentCaveat: "fake is an automated smoke-test fixture only. Normal manual/service runs should leave FAKE_AGENT_SCRIPT unset and use real configured agents."
            ),
            oracle: .init(
                optInGuidance: "oracle_send is external model inference. Use deterministic repo tools first and call oracle_send only when prompted or when explicitly useful.",
                requiredEnvironment: ["RPCE_ORACLE_API_KEY", "OPENROUTER_API_KEY"]
            ),
            exitCodes: [
                .init(code: 0, meaning: "success", retryable: false),
                .init(code: 64, meaning: "command-line usage error", retryable: false),
                .init(code: 65, meaning: "socket authentication rejected", retryable: false),
                .init(code: 66, meaning: "requested root does not exist or is not a directory", retryable: false),
                .init(code: 69, meaning: "runtime environment error", retryable: false)
            ],
            smokeCommands: [
                "rpce-headless --help",
                "rpce-headless dump --json",
                "python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build/debug/rpce-headless \"$PWD\"",
                "python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py .build/debug/rpce-headless \"$PWD\""
            ]
        )
    }

    static func robotDocsGuide(loadedRoots: [String] = []) -> String {
        let roots = loadedRoots.isEmpty ? "current working directory when --root is omitted" : loadedRoots.joined(separator: ", ")
        return """
        # rpce-headless Agent Guide

        Start here:
        1. Run `rpce-headless capabilities --json` or call MCP `headless_capabilities`.
        2. Confirm `loaded_roots`; current value: \(roots).
        3. For direct evidence, use `get_file_tree`, `file_search`, `read_file`, and `workspace_context`.
        4. For curated discovery, prefer `context_builder` with `response_type:"clarify"`.
        5. For delegated read-only work, call `agent_manage` with `op:"list_agents"` first, then use `agent_run` with an available real agent. Always read logs and cleanup terminal sessions.
        6. Use `oracle_send` only on demand; it leaves deterministic repo evidence and asks an external model.

        Transport rules:
        - `rpce-headless serve` over stdio exposes the full tool set.
        - `serve --socket` is discovery-restricted by default.
        - Full-tool sockets require `--expose-all-tools` and `RPCE_SOCKET_AUTH_TOKEN`; `connect --auth` reads that environment variable.

        Context Builder examples:
        - One-shot: `{"instructions":"Map the MCP server entry points","response_type":"clarify"}`
        - Async start: `{"op":"start","instructions":"Map the MCP server entry points","response_type":"clarify","token_budget":160000,"timeout_seconds":900}`
        - Wait: `{"op":"wait","context_id":"<context_id>","timeout":30}`
        - Result: `{"op":"get_result","context_id":"<context_id>"}`
        - Cleanup: `{"op":"cleanup","context_id":"<context_id>"}`

        Agent runner examples:
        - List agents: `{"op":"list_agents"}`
        - Start read-only subagent: `{"op":"start","model_id":"claude","message":"Read-only: inspect architecture and cite files.","detach":true,"timeout":0}`
        - Wait: `{"op":"wait","session_id":"<session_id>","timeout":60}`
        - Logs: `{"op":"get_log","session_id":"<session_id>","limit":40}`
        - Cleanup: `{"op":"cleanup_sessions","session_ids":["<session_id>"]}`

        Fake-agent caveat:
        `fake` is reserved for automated smoke harnesses. Normal manual/service runs should leave `FAKE_AGENT_SCRIPT` unset and use real configured agents.
        """
    }
}

struct HeadlessCapabilitiesReply: Codable, Equatable {
    struct RootSemantics: Codable, Equatable {
        let defaultBehavior: String
        let globalCodexRecommendation: String

        enum CodingKeys: String, CodingKey {
            case defaultBehavior = "default_behavior"
            case globalCodexRecommendation = "global_codex_recommendation"
        }
    }

    struct Transport: Codable, Equatable {
        let name: String
        let exposure: String
        let tools: [String]
        let authentication: String
    }

    struct ContextBuilderGuide: Codable, Equatable {
        let syncExample: String
        let asyncStartExample: String
        let asyncWaitExample: String
        let asyncResultExample: String
        let cleanupExample: String
        let timeoutGuidance: String

        enum CodingKeys: String, CodingKey {
            case syncExample = "sync_example"
            case asyncStartExample = "async_start_example"
            case asyncWaitExample = "async_wait_example"
            case asyncResultExample = "async_result_example"
            case cleanupExample = "cleanup_example"
            case timeoutGuidance = "timeout_guidance"
        }
    }

    struct AgentRunGuide: Codable, Equatable {
        let listAgentsExample: String
        let startExample: String
        let waitExample: String
        let logExample: String
        let cleanupExample: String
        let fakeAgentCaveat: String

        enum CodingKeys: String, CodingKey {
            case listAgentsExample = "list_agents_example"
            case startExample = "start_example"
            case waitExample = "wait_example"
            case logExample = "log_example"
            case cleanupExample = "cleanup_example"
            case fakeAgentCaveat = "fake_agent_caveat"
        }
    }

    struct OracleGuide: Codable, Equatable {
        let optInGuidance: String
        let requiredEnvironment: [String]

        enum CodingKeys: String, CodingKey {
            case optInGuidance = "opt_in_guidance"
            case requiredEnvironment = "required_environment"
        }
    }

    struct ExitCode: Codable, Equatable {
        let code: Int
        let meaning: String
        let retryable: Bool
    }

    let toolName: String
    let serverVersion: String
    let contractVersion: String
    let loadedRoots: [String]
    let rootSemantics: RootSemantics
    let transports: [Transport]
    let recommendedWorkflow: [String]
    let contextBuilder: ContextBuilderGuide
    let agentRun: AgentRunGuide
    let oracle: OracleGuide
    let exitCodes: [ExitCode]
    let smokeCommands: [String]

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case serverVersion = "server_version"
        case contractVersion = "contract_version"
        case loadedRoots = "loaded_roots"
        case rootSemantics = "root_semantics"
        case transports
        case recommendedWorkflow = "recommended_workflow"
        case contextBuilder = "context_builder"
        case agentRun = "agent_run"
        case oracle
        case exitCodes = "exit_codes"
        case smokeCommands = "smoke_commands"
    }
}
