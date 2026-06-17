import Foundation
import MCP

enum HeadlessCapabilities {
    static let contractVersion = "1"

    static func make(loadedRoots: [String]) -> HeadlessCapabilitiesReply {
        make(loadedRootMetadata: HeadlessRootMetadataFactory.metadata(for: loadedRoots))
    }

    static func make(loadedRootMetadata: [HeadlessRootMetadata]) -> HeadlessCapabilitiesReply {
        HeadlessCapabilitiesReply(
            toolName: "rpce-headless",
            serverVersion: HeadlessMCPServer.version,
            contractVersion: contractVersion,
            loadedRoots: loadedRootMetadata.map(\.path),
            loadedRootMetadata: loadedRootMetadata,
            rootWarnings: HeadlessRootMetadataFactory.warnings(for: loadedRootMetadata),
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
                "Call headless_status or rpce-headless robot-docs status --json first for compact workspace triage.",
                "Use headless_capabilities or rpce-headless capabilities --json next when you need the fuller contract, examples, exit codes, and smoke commands.",
                "Verify loaded_roots and root_warnings before exploring.",
                "Follow native RepoPrompt workflow shapes when planning complex work: cheap explore-style probes, context_builder for curated selection/synthesis, then pair/design critique or implementation.",
                "For repo onboarding, architecture mapping, or implementation planning, use context_builder before hand-rolling broad file-by-file exploration.",
                "Use get_file_tree, file_search, read_file, and get_code_structure for direct evidence and citations after the synthesis path identifies anchors.",
                "When independent review helps, use the rpce-headless server-managed subagent lifecycle: agent_manage list_agents, agent_run a bounded read-only task, wait or poll, get logs, then cleanup_sessions. Do not substitute client-local ad hoc subagents for this contract.",
                "Use oracle_send only when explicitly requested or when external inference is appropriate."
            ],
            architectureOnboarding: .default,
            nativeWorkflows: .repoPromptNative,
            contextBuilder: .init(
                syncExample: #"{"instructions":"Map this repo","response_type":"clarify"}  // compatibility: returns original result shape if completed inside the sync cap, otherwise a running snapshot with context_id"#,
                asyncStartExample: #"{"op":"start","instructions":"Map this repo","response_type":"clarify","token_budget":160000,"timeout_seconds":900}"#,
                asyncWaitExample: #"{"op":"wait","context_id":"<context_id>","timeout":30}"#,
                asyncResultExample: #"{"op":"get_result","context_id":"<context_id>"}"#,
                cleanupExample: #"{"op":"cleanup","context_id":"<context_id>"}"#,
                timeoutGuidance: "timeout_seconds caps the spawned discovery-agent lifetime on start/compatibility runs. Omitting op is MCP-safe compatibility mode: short completed calls return the original result shape, while calls that reach the short sync cap return a running lifecycle snapshot with context_id and next_action. For op=wait, use timeout for the client wait window; timeout_seconds is accepted as an alias, timeout wins when both are present, and large waits are capped to a progress-friendly maximum. Operators can raise the cap with RPCE_CONTEXT_BUILDER_WAIT_MAX_SECONDS when a client truly wants longer waits. If the MCP client supplies a progress token, rpce-headless emits notifications/progress heartbeats while waiting."
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
                "rpce-headless robot-docs status --json",
                "rpce-headless dump --json",
                "python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build/debug/rpce-headless \"$PWD\"",
                "python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py .build/debug/rpce-headless \"$PWD\""
            ]
        )
    }

    static func status(loadedRoots: [String], discoveryRestricted: Bool = false) -> HeadlessStatusReply {
        status(loadedRootMetadata: HeadlessRootMetadataFactory.metadata(for: loadedRoots), discoveryRestricted: discoveryRestricted)
    }

    static func status(loadedRootMetadata: [HeadlessRootMetadata], discoveryRestricted: Bool = false) -> HeadlessStatusReply {
        let capabilities = make(loadedRootMetadata: loadedRootMetadata)
        let fullTransport = capabilities.transports.first { $0.name == "stdio" }
        let socketTransport = capabilities.transports.first { $0.name == "socket" }
        let rootWarnings = HeadlessRootMetadataFactory.warnings(for: loadedRootMetadata)
        let currentTransportName = discoveryRestricted ? "socket" : "stdio"
        let currentExposure = discoveryRestricted
            ? (socketTransport?.exposure ?? "discovery_restricted")
            : (fullTransport?.exposure ?? "full")
        let availableHere = discoveryRestricted
            ? HeadlessToolSchemas.discoveryToolNames
            : Set(HeadlessToolSchemas.tools.map(\.name))
        let suggestedFirstToolCalls = if discoveryRestricted {
            [
                "headless_status",
                #"workspace_context {"include":["tree","tokens"]}"#,
                #"file_search {"pattern":"AGENTS.md|README|CONTEXT.md|docs/adr|Package.swift","mode":"both","regex":true,"max_results":20}"#,
                "headless_capabilities"
            ]
        } else {
            [
                "headless_status",
                #"context_builder {"op":"start","instructions":"Map the repo architecture, identify implementation seams, and select the key files before manual reads.","response_type":"clarify","token_budget":160000,"timeout_seconds":900}"#,
                #"agent_manage {"op":"list_agents"}"#,
                #"agent_run {"op":"start","message":"Read-only: independently inspect the architecture and cite likely change files.","detach":true,"timeout":0}"#,
                #"workspace_context {"include":["tree","tokens"]}"#,
                #"file_search {"pattern":"AGENTS.md|README|CONTEXT.md|docs/adr|Package.swift","mode":"both","regex":true,"max_results":20}"#,
                "headless_capabilities"
            ]
        }
        let agentGuidance = discoveryRestricted
            ? "This discovery-restricted socket only exposes direct repo evidence tools. Use full stdio, or an authenticated full-tool socket, for context_builder, agent_manage, agent_run, and oracle_send."
            : "Use context_builder for curated architecture discovery; use the rpce-headless server-managed subagent lifecycle through agent_manage plus bounded read-only agent_run; keep oracle_send opt-in/on-demand."
        return HeadlessStatusReply(
            toolName: capabilities.toolName,
            serverVersion: capabilities.serverVersion,
            contractVersion: capabilities.contractVersion,
            status: rootWarnings.isEmpty ? "ready" : "needs_attention",
            currentDirectory: HeadlessRootMetadataFactory.currentDirectory(),
            loadedRoots: capabilities.loadedRoots,
            loadedRootMetadata: loadedRootMetadata,
            rootWarnings: rootWarnings,
            mcpExposure: .init(
                currentTransport: currentTransportName,
                currentExposure: currentExposure,
                availableTools: availableHere.sorted(),
                stdio: fullTransport?.exposure ?? "full",
                socketDefault: socketTransport?.exposure ?? "discovery_restricted",
                discoveryRestrictedTools: HeadlessToolSchemas.discoveryToolNames.sorted(),
                fullTools: HeadlessToolSchemas.tools.map(\.name).sorted()
            ),
            availableAgentTools: .init(
                contextBuilder: availableHere.contains("context_builder"),
                agentRun: availableHere.contains("agent_run"),
                agentManage: availableHere.contains("agent_manage"),
                oracleSend: availableHere.contains("oracle_send"),
                fullStdioTools: ["context_builder", "agent_manage", "agent_run", "oracle_send"],
                guidance: agentGuidance
            ),
            suggestedFirstToolCalls: suggestedFirstToolCalls,
            architectureOnboarding: .default,
            nativeWorkflows: .repoPromptNative,
            smokeCommands: capabilities.smokeCommands
        )
    }

    static func robotDocsGuide(loadedRoots: [String] = []) -> String {
        let roots = loadedRoots.isEmpty ? "current working directory when --root is omitted" : loadedRoots.joined(separator: ", ")
        return """
        # rpce-headless Agent Guide

        Start here:
        0. For a compact machine-readable workspace check, run `rpce-headless robot-docs status --json` or call MCP `headless_status`.
        1. Run `rpce-headless capabilities --json` or call MCP `headless_capabilities`.
        2. Confirm `loaded_roots`; current value: \(roots).
        3. For repo onboarding, architecture mapping, or implementation planning, prefer `context_builder` with `response_type:"clarify"` before broad manual reads.
        4. For delegated read-only work, use the server-managed subagent lifecycle: call `agent_manage` with `op:"list_agents"` first, then use `agent_run` with an available real agent. Always read logs and cleanup terminal sessions through `agent_manage`.
        5. For direct evidence and citations, use `get_file_tree`, `file_search`, `read_file`, `get_code_structure`, and `workspace_context`.
        6. Use `oracle_send` only on demand; it leaves deterministic repo evidence and asks an external model.

        Native RepoPrompt workflow shapes:
        - Roles: `explore` for cheap read-only probes, `engineer` for balanced implementation, `pair` for highest-tier main-line investigation/implementation, `design` for bounded architecture critique.
        - Investigate: orchestrator stays lean, optional explore probes gather external/prior facts, `context_builder` curates selection, one `pair` investigator does the main line, then oracle/chat synthesizes over the curated selection.
        - Optimize: fan out narrow `explore` probes for bottlenecks/callgraph/conventions/scope, use `context_builder` for metric/scope/candidates, then delegate one measured change at a time to `pair`.
        - Deep Plan: use `explore` probes for seams/prior art, `context_builder` for architectural bones, one bounded `design` critique, then the orchestrator writes the final plan.
        - Subagents are scoped: avoid recursive swarms; use cheap/narrow explore-style probes before stronger pair/design work.
        - Custom workflows: native app workflows can be custom markdown templates. Headless v1 exposes this as metadata/extension guidance; do not assume `workflow_name`/`workflow_id` works in headless `agent_run` until the headless workflow resolver is implemented.

        Transport rules:
        - `rpce-headless serve` over stdio exposes the full tool set.
        - `serve --socket` is discovery-restricted by default.
        - Full-tool sockets require `--expose-all-tools` and `RPCE_SOCKET_AUTH_TOKEN`; `connect --auth` reads that environment variable.

        Architecture onboarding recipe:
        1. Confirm roots with `headless_status` and check `root_warnings`.
        2. Start `context_builder` with `response_type:"clarify"` instead of hand-rolling a broad summary.
        3. If independent review helps, call `agent_manage {"op":"list_agents"}` and run a bounded server-managed `agent_run` task.
        4. Request a shallow tree: `{"mode":"full","max_depth":2}`.
        5. Search anchor docs and entry points: `AGENTS.md|README|CONTEXT.md|docs/adr|Package.swift`.
        6. Call `get_code_structure` on likely entry-point files, then follow its structured fallback tools when codemap data is unavailable.

        Context Builder examples:
        - Compatibility one-shot: `{"instructions":"Map the MCP server entry points","response_type":"clarify"}` starts a pollable run. If it completes inside the sync cap it returns the original result shape; otherwise it returns a running lifecycle snapshot with `context_id`.
        - Async start: `{"op":"start","instructions":"Map the MCP server entry points","response_type":"clarify","token_budget":160000,"timeout_seconds":900}`
        - Current/latest run: pass `"context_id":"active"` or `"current"` to poll/wait/get_result/cancel/cleanup the active run, or the latest completed run until cleanup.
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

    struct ArchitectureOnboardingGuide: Codable, Equatable {
        let intent: String
        let steps: [String]
        let preferredSummaryTool: String
        let delegationGuidance: String
        let oracleGuidance: String

        static let `default` = ArchitectureOnboardingGuide(
            intent: "Quickly verify the workspace, then use curated discovery before manual file-by-file exploration.",
            steps: [
                "Confirm loaded_root_metadata and root_warnings via headless_status; use headless_capabilities afterward when the fuller contract is needed.",
                "Start context_builder with response_type=clarify for architecture mapping, implementation planning, or any task that needs synthesis.",
                "Use agent_manage list_agents, then bounded read-only agent_run, when a second pass or independent review would reduce guesswork.",
                "Use get_file_tree and file_search to verify anchor docs and entry points found by curated discovery.",
                "Call get_code_structure on likely entry-point files; if a file has no codemap, follow the structured file_search/read_file fallback."
            ],
            preferredSummaryTool: "context_builder",
            delegationGuidance: "Use the rpce-headless server-managed subagent lifecycle: agent_manage list_agents before bounded read-only agent_run tasks; inspect logs and cleanup terminal sessions. Do not substitute client-local ad hoc subagents for this contract.",
            oracleGuidance: "Use oracle_send only when explicitly requested or when external inference is intentionally useful."
        )

        enum CodingKeys: String, CodingKey {
            case intent
            case steps
            case preferredSummaryTool = "preferred_summary_tool"
            case delegationGuidance = "delegation_guidance"
            case oracleGuidance = "oracle_guidance"
        }
    }

    struct NativeWorkflowGuide: Codable, Equatable {
        struct Role: Codable, Equatable {
            let name: String
            let purpose: String
            let bounds: String
        }

        struct Workflow: Codable, Equatable {
            let name: String
            let intent: String
            let shape: [String]
        }

        struct CustomWorkflowExtensibility: Codable, Equatable {
            let currentHeadlessSupport: String
            let appNativeSupport: [String]
            let storage: [String]
            let futureHeadlessContract: [String]
            let agentCreationGuidance: [String]

            enum CodingKeys: String, CodingKey {
                case currentHeadlessSupport = "current_headless_support"
                case appNativeSupport = "app_native_support"
                case storage
                case futureHeadlessContract = "future_headless_contract"
                case agentCreationGuidance = "agent_creation_guidance"
            }
        }

        let source: String
        let distinction: String
        let roles: [Role]
        let compositionRules: [String]
        let workflows: [Workflow]
        let customWorkflows: CustomWorkflowExtensibility

        static let repoPromptNative = NativeWorkflowGuide(
            source: "RepoPrompt CE native product workflow prompts, not Smithers workflows.",
            distinction: "These are composition patterns for using rpce-headless tools. Headless v1 exposes built-in/custom workflow metadata and extension points; app-native Agent Mode owns direct workflow selection and settings mutation today.",
            roles: [
                .init(name: "explore", purpose: "cheap read-only probes and codebase mapping", bounds: "short-lived, fresh context, narrow scope, no edits, no oracle, no recursive full agent_run"),
                .init(name: "engineer", purpose: "balanced implementation work", bounds: "use for normal build/fix tasks when a stronger pair role is unnecessary"),
                .init(name: "pair", purpose: "highest-tier main-line investigation, implementation, or pair-programming work", bounds: "use after cheap context gathering; may use narrow read-only explore children in native app workflows"),
                .init(name: "design", purpose: "architecture critique, design review, and planning feedback", bounds: "bounded critique/report role, not a broad research swarm")
            ],
            compositionRules: [
                "The top-level agent orchestrates; it should not manually read every file when a workflow can gather and curate context.",
                "Use cheap/narrow explore-style probes for facts, seams, callgraphs, conventions, and prior art.",
                "Use context_builder to curate selection and synthesize architectural bones before stronger critique or implementation.",
                "Use pair/design for the main line or bounded critique after shared evidence exists.",
                "Keep subagents scoped; avoid recursive free-for-all swarms and overlapping duplicate investigations."
            ],
            workflows: [
                .init(
                    name: "investigate",
                    intent: "Read-only investigation and root-cause analysis.",
                    shape: [
                        "Orchestrator triages symptoms and hypotheses.",
                        "Optional explore-style probes gather external facts, git archaeology, or prior docs.",
                        "context_builder curates relevant workspace selection.",
                        "One pair investigator follows the main line and records evidence.",
                        "Orchestrator spot-checks claims, refocuses selection, and synthesizes."
                    ]
                ),
                .init(
                    name: "optimize",
                    intent: "Measured performance or quality improvement loop.",
                    shape: [
                        "Translate the user target into repo nouns.",
                        "Fan out narrow explore-style probes for bottlenecks, callgraph, conventions, prior perf work, and scope.",
                        "context_builder designs metric, instrumentation, baseline, and first candidates.",
                        "pair lands one attributed change per loop iteration and records measurements.",
                        "Orchestrator asks for stop/continue decisions over the shared scoreboard."
                    ]
                ),
                .init(
                    name: "deep_plan",
                    intent: "Delegation-heavy planning that ends in a polished plan, not implementation.",
                    shape: [
                        "Use explore-style probes to map seams, prior art, and external dependencies.",
                        "context_builder produces architectural bones and key files.",
                        "A bounded design agent critiques the draft direction.",
                        "The orchestrator writes and polishes the final executable plan."
                    ]
                )
            ],
            customWorkflows: .init(
                currentHeadlessSupport: "metadata_only",
                appNativeSupport: [
                    "AgentWorkflowStore loads custom markdown workflows from the app Workflows folder.",
                    "Agent Mode settings manage built-in workflow visibility, featured workflows, and custom workflow markdown.",
                    "App MCP agent_run accepts workflow_id or workflow_name and app agent_manage can list workflows.",
                    "RepoPrompt app settings are MCP-manipulable for supported settings; workflow creation/mutation should use the app-native workflow store/settings surface when exposed."
                ],
                storage: [
                    "Custom workflows are markdown-backed AgentWorkflowDefinition records.",
                    "Templates strip YAML frontmatter and replace $ARGUMENTS with the user request.",
                    "Built-in workflows can be cloned into custom workflows in the app."
                ],
                futureHeadlessContract: [
                    "Expose workflow listing in headless agent_manage once headless can read a workflow store or config.",
                    "Allow agent_run workflow_name/workflow_id only after headless can resolve and wrap templates deterministically.",
                    "Expose create/update/delete custom workflow operations through an explicit settings/workflow tool with validation, provenance, and no partial writes.",
                    "Keep custom workflows separate from Smithers workflows and from external slash skills."
                ],
                agentCreationGuidance: [
                    "Agents may propose custom workflow markdown using the same native role/composition rules.",
                    "Until mutation is implemented, agents should surface proposed workflow content and intended settings changes rather than silently writing global workflow settings.",
                    "Custom workflows should define narrow triggers, role choreography, expected artifacts, cleanup rules, and how context_builder/subagents share evidence."
                ]
            )
        )

        enum CodingKeys: String, CodingKey {
            case source
            case distinction
            case roles
            case compositionRules = "composition_rules"
            case workflows
            case customWorkflows = "custom_workflows"
        }
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
    let loadedRootMetadata: [HeadlessRootMetadata]
    let rootWarnings: [HeadlessRootWarning]
    let rootSemantics: RootSemantics
    let transports: [Transport]
    let recommendedWorkflow: [String]
    let architectureOnboarding: ArchitectureOnboardingGuide
    let nativeWorkflows: NativeWorkflowGuide
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
        case loadedRootMetadata = "loaded_root_metadata"
        case rootWarnings = "root_warnings"
        case rootSemantics = "root_semantics"
        case transports
        case recommendedWorkflow = "recommended_workflow"
        case architectureOnboarding = "architecture_onboarding"
        case nativeWorkflows = "native_workflows"
        case contextBuilder = "context_builder"
        case agentRun = "agent_run"
        case oracle
        case exitCodes = "exit_codes"
        case smokeCommands = "smoke_commands"
    }
}

struct HeadlessStatusReply: Codable, Equatable {
    struct MCPExposure: Codable, Equatable {
        let currentTransport: String
        let currentExposure: String
        let availableTools: [String]
        let stdio: String
        let socketDefault: String
        let discoveryRestrictedTools: [String]
        let fullTools: [String]

        enum CodingKeys: String, CodingKey {
            case currentTransport = "current_transport"
            case currentExposure = "current_exposure"
            case availableTools = "available_tools"
            case stdio
            case socketDefault = "socket_default"
            case discoveryRestrictedTools = "discovery_restricted_tools"
            case fullTools = "full_tools"
        }
    }

    struct AvailableAgentTools: Codable, Equatable {
        let contextBuilder: Bool
        let agentRun: Bool
        let agentManage: Bool
        let oracleSend: Bool
        let fullStdioTools: [String]
        let guidance: String

        enum CodingKeys: String, CodingKey {
            case contextBuilder = "context_builder"
            case agentRun = "agent_run"
            case agentManage = "agent_manage"
            case oracleSend = "oracle_send"
            case fullStdioTools = "full_stdio_tools"
            case guidance
        }
    }

    let toolName: String
    let serverVersion: String
    let contractVersion: String
    let status: String
    let currentDirectory: String
    let loadedRoots: [String]
    let loadedRootMetadata: [HeadlessRootMetadata]
    let rootWarnings: [HeadlessRootWarning]
    let mcpExposure: MCPExposure
    let availableAgentTools: AvailableAgentTools
    let suggestedFirstToolCalls: [String]
    let architectureOnboarding: HeadlessCapabilitiesReply.ArchitectureOnboardingGuide
    let nativeWorkflows: HeadlessCapabilitiesReply.NativeWorkflowGuide
    let smokeCommands: [String]

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case serverVersion = "server_version"
        case contractVersion = "contract_version"
        case status
        case currentDirectory = "current_directory"
        case loadedRoots = "loaded_roots"
        case loadedRootMetadata = "loaded_root_metadata"
        case rootWarnings = "root_warnings"
        case mcpExposure = "mcp_exposure"
        case availableAgentTools = "available_agent_tools"
        case suggestedFirstToolCalls = "suggested_first_tool_calls"
        case architectureOnboarding = "architecture_onboarding"
        case nativeWorkflows = "native_workflows"
        case smokeCommands = "smoke_commands"
    }
}
