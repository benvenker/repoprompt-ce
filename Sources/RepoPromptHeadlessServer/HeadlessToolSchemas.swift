import MCP

enum HeadlessToolSchemas {
    static let discoveryToolNames: Set<String> = [
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
            name: "read_file",
            description: "Read file contents with optional line range. Parameters: path (required), start_line (1-based or negative tail), limit.",
            inputSchema: object([
                "path": string("File path"),
                "start_line": integer("Line to start from (1-based), or negative for tail behavior"),
                "limit": integer("Number of lines to read")
            ], required: ["path"]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "get_file_tree",
            description: "Generate ASCII directory tree. type: files|roots; mode: auto|full|folders|selected. Single-workspace headless server; no worktree metadata.",
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
            description: "Search paths and/or file contents. Supports pattern, mode auto|path|content|both, regex, max_results, filter.extensions, filter.paths, filter.exclude, context_lines, whole_word, count_only.",
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
            description: "Return code structure for explicit paths or current selection. Parameters: scope paths|selected, paths, max_results.",
            inputSchema: object([
                "scope": string("Scope", enumValues: ["paths", "selected"]),
                "paths": array(string("File or directory path"), "Paths when scope='paths'"),
                "max_results": integer("Maximum codemaps to render")
            ]),
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
            description: "Render prompt context for the single headless workspace. Includes prompt, selection/file tree, selected file contents, and token totals by default.",
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
            name: "agent_run",
            description: "Start and control headless process-backed agents for this rpce-headless server. Full stdio mode only; discovery-restricted sockets do not expose this tool. Supported ops: start, poll, wait, cancel.",
            inputSchema: object([
                "op": string(operationDescription, enumValues: ["start", "poll", "wait", "cancel"]),
                "message": string("Message/prompt for op=start"),
                "model_id": string("Configured headless agent name from agent_manage list_agents; defaults to RPCE_AGENT_RUN_DEFAULT_AGENT or claude"),
                "session_name": string("Optional display name for the headless process session"),
                "detach": boolean("For op=start, return immediately after launching instead of waiting"),
                "timeout": integer("Timeout in seconds for start/wait; 0 behaves like poll"),
                "session_id": string("Headless session id for poll, wait, or cancel")
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
        ),
        Tool(
            name: "agent_manage",
            description: "Inspect and manage headless process-backed agent sessions for this rpce-headless server. These are not app/window Agent Mode sessions. Supported ops: list_agents, list_sessions, get_log, stop_session, cleanup_sessions.",
            inputSchema: object([
                "op": string(operationDescription, enumValues: ["list_agents", "list_sessions", "get_log", "stop_session", "cleanup_sessions"]),
                "session_id": string("Headless session id for get_log or stop_session"),
                "session_ids": array(string("Headless session id"), "Session ids for cleanup_sessions"),
                "state": string("Optional state filter for list_sessions", enumValues: ["running", "completed", "failed", "cancelled"]),
                "limit": integer("Maximum sessions or log turns to return"),
                "offset": integer("Log turn offset for get_log")
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
        ),
        Tool(
            name: "context_builder",
            description: "Headless Context Builder orchestration. Launches a configured discovery agent over a restricted local MCP socket, harvests the selected context and handoff prompt, and optionally asks the oracle for question/plan/review responses. export_response is currently unsupported in headless v1.",
            inputSchema: object([
                "instructions": string("Discovery instructions for the Context Builder agent"),
                "response_type": string("clarify returns context only; question/plan/review ask the oracle after discovery", enumValues: ["clarify", "question", "plan", "review"]),
                "export_response": boolean("Unsupported in headless v1; true returns a clear tool error"),
                "token_budget": integer("Optional token budget override"),
                "timeout_seconds": integer("Optional discovery agent timeout override")
            ], required: ["instructions"]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
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
}
