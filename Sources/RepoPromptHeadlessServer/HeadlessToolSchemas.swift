import MCP

enum HeadlessToolSchemas {
    static let discoveryToolNames: Set<String> = [
        "headless_capabilities",
        "headless_status",
        "manage_selection",
        "prompt",
        "workspace_context",
        "get_file_tree",
        "get_code_structure",
        "file_search",
        "read_file"
    ]

    static var discoveryTools: [Tool] {
        tools.filter { discoveryToolNames.contains($0.name) }
    }

    static let tools: [Tool] = [
        Tool(
            name: "headless_status",
            description: "Return the compact first-call workspace triage packet: loaded root metadata, root mismatch warnings, MCP exposure mode, available agent tools, suggested first tool calls, native RepoPrompt workflow shapes, architecture onboarding recipe, and smoke commands.",
            inputSchema: object([:]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "headless_capabilities",
            description: "Return the fuller agent-readable rpce-headless contract after compact status triage: loaded_roots plus loaded_root_metadata, root warnings, stdio vs socket tool exposure, native RepoPrompt workflow shapes, architecture onboarding workflow, context_builder examples, agent_manage/agent_run pattern, oracle opt-in guidance, fake-agent caveat, exit codes, and smoke commands.",
            inputSchema: object([:]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "context_builder",
            description: "Preferred repo-onboarding and architecture-synthesis tool. Use this early for tasks like 'map this repo', 'find the implementation seam', or 'build a grounded plan' instead of manually clipping through many read_file calls. For planning/onboarding, prefer op=start then poll/wait/get_result/cleanup; context_id:\"active\" or \"current\" addresses the active run, or the latest completed run until cleanup. Omitting op is compatibility mode: it starts a pollable run and waits only up to a short MCP-safe cap; short completed calls return the original result shape and are cleaned up by the server, while longer calls return a running lifecycle snapshot with context_id and next_action. Full stdio mode only; discovery-restricted sockets do not expose this tool. export_response is unsupported in headless v1.",
            inputSchema: contextBuilderInputSchema(),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
        ),
        Tool(
            name: "agent_manage",
            description: "Manage the rpce-headless server's subagent pool and sessions. Use this instead of client-local/ad hoc subagents when repo discovery needs independent review. Start with list_agents, then use agent_run only for a server-managed bounded task; use list_sessions/get_log/cleanup_sessions to supervise and collect evidence. These are not app/window Agent Mode sessions. Supported ops: list_agents, list_sessions, get_log, stop_session, cleanup_sessions.",
            inputSchema: object([
                "op": string(operationDescription, enumValues: ["list_agents", "list_sessions", "get_log", "stop_session", "cleanup_sessions"]),
                "session_id": string("Headless session id for get_log or stop_session"),
                "session_ids": array(string("Headless session id"), "Session ids for cleanup_sessions"),
                "state": string("Optional state filter for list_sessions", enumValues: ["running", "cancelling", "completed", "failed", "cancelled"]),
                "limit": integer("Maximum sessions or log turns to return"),
                "offset": integer("Log turn offset for get_log")
            ], required: ["op"]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
        ),
        Tool(
            name: "agent_run",
            description: "Start or control one bounded task in the rpce-headless server-managed subagent lifecycle. Do not treat this as generic client-local agent spawning: first call agent_manage list_agents, choose an available server-configured agent, wait/poll, inspect logs through agent_manage, and cleanup terminal sessions. Full stdio mode only; discovery-restricted sockets do not expose this tool. Supported ops: start, poll, wait, cancel.",
            inputSchema: object([
                "op": string(operationDescription, enumValues: ["start", "poll", "wait", "cancel"]),
                "message": string("Message/prompt for op=start"),
                "model_id": string("Configured headless agent name from agent_manage list_agents; defaults to RPCE_AGENT_RUN_DEFAULT_AGENT or claude"),
                "session_name": string("Optional display name for the headless process session"),
                "detach": boolean("For op=start, return immediately after launching instead of waiting"),
                "timeout": integer("Timeout in seconds for start/wait; 0 behaves like poll"),
                "session_id": string("Headless session id for poll, wait, or cancel")
            ], required: ["op"]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
        ),
        Tool(
            name: "get_file_tree",
            description: "Generate ASCII directory tree for quick orientation and evidence. For architecture synthesis or planning, call context_builder before relying on repeated tree/search/read loops. type: files|roots; mode: auto|full|folders|selected. Single-workspace headless server; no worktree metadata.",
            inputSchema: object([
                "type": string("Tree type", enumValues: ["files", "roots"]),
                "mode": string("Filter mode", enumValues: ["auto", "full", "folders", "selected"]),
                "max_depth": integer("Maximum depth (root = 0)"),
                "path": string("Optional starting folder")
            ]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "file_search",
            description: "Search paths and/or file contents for direct evidence. For broad repo onboarding, use context_builder first, then use file_search to verify anchors and citations. Supports pattern, mode auto|path|content|both, regex, max_results, filter.extensions, filter.paths, filter.exclude, context_lines, whole_word, count_only.",
            inputSchema: object([
                "pattern": string("Search pattern"),
                "mode": string("Search scope", enumValues: ["auto", "path", "content", "both"]),
                "regex": boolean("Use regex matching"),
                "case_insensitive": boolean("Case-insensitive search"),
                "max_results": integer("Maximum total results"),
                "context_lines": integer("Lines of context before/after matches"),
                "whole_word": boolean("Match whole words only"),
                "count_only": boolean("Return counts only"),
                "filter": object([
                    "extensions": array(string("Extension like .swift"), "Only search files with these extensions"),
                    "paths": array(string("Path or folder"), "Limit search to paths/folders"),
                    "exclude": array(string("Exclude pattern"), "Skip matching paths")
                ])
            ], required: ["pattern"]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "get_code_structure",
            description: "Return code structure for explicit files or current selection. Best used after context_builder or file_search identifies likely entry points. Parameters: scope paths|selected, paths, max_results. Structured content lists each resolved file, whether a codemap is available, unresolved paths, and the file_search/read_file fallback for no-codemap files.",
            inputSchema: object([
                "scope": string("Scope", enumValues: ["paths", "selected"]),
                "paths": array(string("File or directory path"), "Paths when scope='paths'"),
                "max_results": integer("Maximum codemaps to render")
            ]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "read_file",
            description: "Read file contents with optional line range for evidence and citations. For onboarding/planning, prefer context_builder first and use read_file for the specific files it or search identifies. Parameters: path (required), start_line (1-based or negative tail), limit.",
            inputSchema: object([
                "path": string("File path"),
                "start_line": integer("Line to start from (1-based), or negative for tail behavior"),
                "limit": integer("Number of lines to read")
            ], required: ["path"]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "manage_selection",
            description: "Manage selected files for workspace_context. Headless v1 supports get/add/remove/set/clear with full or codemap_only. Slices, preview, promote, and demote return explicit unsupported errors.",
            inputSchema: object([
                "op": string("Operation", enumValues: ["get", "add", "remove", "set", "clear", "preview", "promote", "demote"]),
                "paths": array(string("Relative or absolute file/folder path"), "File or folder paths"),
                "mode": string("Selection representation", enumValues: ["full", "codemap_only", "slices"]),
                "slices": array(object(["path": string("File path")]), "Unsupported in headless v1"),
                "view": string("Accepted for schema compatibility; get returns a JSON summary", enumValues: ["summary", "files", "content", "codemaps"]),
                "path_display": string("Accepted for schema compatibility", enumValues: ["relative", "full"]),
                "strict": boolean("Accepted for schema compatibility")
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        ),
        Tool(
            name: "workspace_context",
            description: "Render prompt context for the single headless workspace. Structured content includes loaded_roots, prompt, selection/file tree, selected file contents, missing/invalid paths, and token totals by default.",
            inputSchema: object([
                "include": array(string("prompt|selection|tree|files|tokens"), "Sections to include")
            ]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "prompt",
            description: "Get or update the in-memory headless prompt. Supports get, set, append, clear. Presets/export are unsupported in v1.",
            inputSchema: object([
                "op": string("Operation", enumValues: ["get", "set", "append", "clear", "export", "list_presets", "select_preset"]),
                "text": string("Text for set/append"),
                "path": string("Unsupported export path"),
                "preset": string("Unsupported preset")
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        ),
        Tool(
            name: "oracle_send",
            description: "Send a message to the configured OpenRouter/OpenAI-compatible oracle. Parameters: message (required), chat_id to continue, model override, include_context. include_context defaults to true for a new chat and false for continuations. Requires RPCE_ORACLE_API_KEY or OPENROUTER_API_KEY; deterministic tools still work without a key.",
            inputSchema: object([
                "message": string("Message to send to the oracle"),
                "chat_id": string("Optional chat id to continue"),
                "model": string("Optional model override; defaults to RPCE_ORACLE_MODEL or openrouter/auto"),
                "include_context": boolean("Include current workspace_context in this request")
            ], required: ["message"]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
        )
    ]

    private static let operationDescription = "Operation"

    private static func object(_ properties: [String: MCP.Value], required: [String] = []) -> MCP.Value {
        var value: [String: MCP.Value] = [
            "type": "object",
            "properties": .object(properties)
        ]
        if !required.isEmpty { value["required"] = .array(required.map { .string($0) }) }
        return .object(value)
    }

    private static func string(_ description: String, enumValues: [String]? = nil) -> MCP.Value {
        var value: [String: MCP.Value] = ["type": "string", "description": .string(description)]
        if let enumValues { value["enum"] = .array(enumValues.map { .string($0) }) }
        return .object(value)
    }

    private static func integer(_ description: String) -> MCP.Value {
        .object(["type": "integer", "description": .string(description)])
    }

    private static func boolean(_ description: String) -> MCP.Value {
        .object(["type": "boolean", "description": .string(description)])
    }

    private static func array(_ items: MCP.Value, _ description: String) -> MCP.Value {
        .object(["type": "array", "description": .string(description), "items": items])
    }

    private static func contextBuilderInputSchema() -> MCP.Value {
        let properties: [String: MCP.Value] = [
            "op": string("Optional lifecycle operation. Prefer start for planning/onboarding runs, then poll/wait/get_result/cancel/cleanup with context_id. Omitting op starts a pollable compatibility run and waits only up to a short MCP-safe cap; completion inside the cap returns the original result shape, otherwise the reply is a lifecycle snapshot.", enumValues: ["start", "poll", "wait", "get_result", "cancel", "cleanup"]),
            "context_id": string("Context Builder run id returned by op=start or synchronous compatibility mode; use active/current to address the active run or latest completed run until cleanup"),
            "instructions": string("Discovery instructions for the Context Builder agent. Example: Map the MCP server entry points and select the key files."),
            "response_type": string("clarify returns context only; question/plan/review ask the oracle after discovery", enumValues: ["clarify", "question", "plan", "review"]),
            "export_response": boolean("Unsupported in headless v1; true returns a clear tool error. Use get_result and workspace_context instead."),
            "token_budget": integer("Optional token budget override"),
            "timeout_seconds": integer("Discovery-agent lifetime cap for start/compatibility runs; also accepted as an op=wait alias for agent intuition. For op=wait, timeout wins when both fields are present and the wait is capped to a progress-friendly maximum."),
            "timeout": integer("Progress-friendly client wait deadline in seconds for op=wait; 0 behaves like poll. This does not kill the discovery agent, and large values are capped so clients receive regular snapshots.")
        ]
        var synchronous: [String: MCP.Value] = [
            "type": "object",
            "properties": .object(properties),
            "required": .array([.string("instructions")])
        ]
        synchronous["not"] = .object(["required": .array([.string("op")])])
        var start = synchronous
        start.removeValue(forKey: "not")
        start["required"] = .array([.string("op"), .string("instructions")])
        start["properties"] = .object(properties.merging([
            "op": .object(["const": .string("start"), "description": .string("Start an async context_builder run")])
        ]) { _, override in override })
        let lifecycleOps: [String] = ["poll", "wait", "get_result", "cancel", "cleanup"]
        let lifecycle: [String: MCP.Value] = [
            "type": "object",
            "properties": .object(properties.merging([
                "op": string("Lifecycle control operation", enumValues: lifecycleOps)
            ]) { _, override in override }),
            "required": .array([.string("op"), .string("context_id")])
        ]
        return .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array([]),
            "oneOf": .array([.object(synchronous), .object(start), .object(lifecycle)])
        ])
    }
}
