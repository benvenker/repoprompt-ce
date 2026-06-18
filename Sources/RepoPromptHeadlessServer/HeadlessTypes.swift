import Foundation
import MCP
import RepoPromptContextCore

struct HeadlessToolFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

struct HeadlessSelectionReply: Codable, Equatable {
    let selectedFiles: [String]
    let codemapFiles: [String]
    let slices: [String: [String]]
    let invalidPaths: [String]
    let mutated: Bool?
    let summary: String

    enum CodingKeys: String, CodingKey {
        case selectedFiles = "selected_files"
        case codemapFiles = "codemap_files"
        case slices
        case invalidPaths = "invalid_paths"
        case mutated
        case summary
    }
}

struct HeadlessWorkspaceContextReply: Codable, Equatable {
    let context: String
    let prompt: String
    let loadedRoots: [String]
    let loadedRootMetadata: [HeadlessRootMetadata]
    let selectedFiles: [String]
    let codemapFiles: [String]
    let totalTokens: Int
    let fileTokens: Int
    let fileTreeTokens: Int
    let missingPaths: [String]
    let invalidPaths: [String]

    enum CodingKeys: String, CodingKey {
        case context
        case prompt
        case loadedRoots = "loaded_roots"
        case loadedRootMetadata = "loaded_root_metadata"
        case selectedFiles = "selected_files"
        case codemapFiles = "codemap_files"
        case totalTokens = "total_tokens"
        case fileTokens = "file_tokens"
        case fileTreeTokens = "file_tree_tokens"
        case missingPaths = "missing_paths"
        case invalidPaths = "invalid_paths"
    }
}

struct HeadlessDumpSummaryReply: Codable, Equatable {
    let loadedRoots: [String]
    let loadedRootMetadata: [HeadlessRootMetadata]
    let rootWarnings: [HeadlessRootWarning]
    let currentDirectory: String
    let rootCount: Int
    let folderCount: Int
    let fileCount: Int
    let generation: UInt64

    enum CodingKeys: String, CodingKey {
        case loadedRoots = "loaded_roots"
        case loadedRootMetadata = "loaded_root_metadata"
        case rootWarnings = "root_warnings"
        case currentDirectory = "current_directory"
        case rootCount = "root_count"
        case folderCount = "folder_count"
        case fileCount = "file_count"
        case generation
    }
}

struct HeadlessRootMetadata: Codable, Equatable {
    let id: String
    let name: String
    let path: String
    let currentDirectoryRelationship: String
    let isCurrentDirectory: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case currentDirectoryRelationship = "current_directory_relationship"
        case isCurrentDirectory = "is_current_directory"
    }
}

struct HeadlessRootWarning: Codable, Equatable {
    let code: String
    let message: String
    let suggestedCommand: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case suggestedCommand = "suggested_command"
    }
}

struct HeadlessCodeStructureReply: Codable, Equatable {
    struct FileResult: Codable, Equatable {
        let path: String
        let fullPath: String
        let rootID: String
        let rootName: String
        let hasStructure: Bool
        let status: String
        let fallbackTools: [String]
        let structure: String?

        enum CodingKeys: String, CodingKey {
            case path
            case fullPath = "full_path"
            case rootID = "root_id"
            case rootName = "root_name"
            case hasStructure = "has_structure"
            case status
            case fallbackTools = "fallback_tools"
            case structure
        }
    }

    let scope: String
    let requestedPaths: [String]
    let unresolvedPaths: [String]
    let files: [FileResult]
    let structureCount: Int
    let fallbackTools: [String]
    let fallbackGuidance: String?
    let text: String

    enum CodingKeys: String, CodingKey {
        case scope
        case requestedPaths = "requested_paths"
        case unresolvedPaths = "unresolved_paths"
        case files
        case structureCount = "structure_count"
        case fallbackTools = "fallback_tools"
        case fallbackGuidance = "fallback_guidance"
        case text
    }
}

enum HeadlessRootMetadataFactory {
    static func currentDirectory() -> String {
        (FileManager.default.currentDirectoryPath as NSString).standardizingPath
    }

    static func metadata(for paths: [String], currentDirectory: String = currentDirectory()) -> [HeadlessRootMetadata] {
        paths.sorted().enumerated().map { index, path in
            let standardized = (path as NSString).standardizingPath
            return HeadlessRootMetadata(
                id: "root-\(index + 1)",
                name: rootName(for: standardized),
                path: standardized,
                currentDirectoryRelationship: relationship(rootPath: standardized, currentDirectory: currentDirectory),
                isCurrentDirectory: standardized == currentDirectory
            )
        }
    }

    static func metadata(for refs: [WorkspaceRootRef], currentDirectory: String = currentDirectory()) -> [HeadlessRootMetadata] {
        refs.sorted { $0.standardizedFullPath < $1.standardizedFullPath }.map { root in
            HeadlessRootMetadata(
                id: root.id.uuidString,
                name: root.name,
                path: root.standardizedFullPath,
                currentDirectoryRelationship: relationship(rootPath: root.standardizedFullPath, currentDirectory: currentDirectory),
                isCurrentDirectory: root.standardizedFullPath == currentDirectory
            )
        }
    }

    static func warnings(for roots: [HeadlessRootMetadata], currentDirectory: String = currentDirectory()) -> [HeadlessRootWarning] {
        guard !roots.isEmpty else {
            return [
                HeadlessRootWarning(
                    code: "no_loaded_roots",
                    message: "No roots are loaded. Start with `rpce-headless serve --root \(currentDirectory)` or run from the repository root.",
                    suggestedCommand: "rpce-headless serve --root \(currentDirectory)"
                )
            ]
        }
        let cwdCovered = roots.contains {
            $0.currentDirectoryRelationship == "current_directory" || $0.currentDirectoryRelationship == "contains_current_directory"
        }
        guard !cwdCovered else { return [] }
        return [
            HeadlessRootWarning(
                code: "current_directory_outside_loaded_roots",
                message: "The process current directory is not inside any loaded root. Agent searches may inspect a different workspace than the shell prompt implies.",
                suggestedCommand: "rpce-headless serve --root \(currentDirectory)"
            )
        ]
    }

    private static func relationship(rootPath: String, currentDirectory: String) -> String {
        let root = (rootPath as NSString).standardizingPath
        let cwd = (currentDirectory as NSString).standardizingPath
        if root == cwd { return "current_directory" }
        if isDescendant(cwd, of: root) { return "contains_current_directory" }
        if isDescendant(root, of: cwd) { return "inside_current_directory" }
        return "outside_current_directory"
    }

    private static func isDescendant(_ path: String, of root: String) -> Bool {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }

    private static func rootName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}

struct HeadlessContextBuildHarvest: Equatable {
    struct File: Equatable {
        let path: String
        let tokens: Int
    }

    let selectedFiles: [File]
    let codemapFiles: [String]
    let prompt: String
    let totalTokens: Int
    let context: String
}

enum HeadlessContextBuilderRunStatus: String, Codable {
    case running
    case cancelling
    case completed
    case failed
    case cancelled
    case expired

    var isTerminal: Bool {
        switch self {
        case .running, .cancelling:
            false
        case .completed, .failed, .cancelled, .expired:
            true
        }
    }
}

struct HeadlessContextBuilderDiagnostics: Codable, Equatable {
    let stdout: String
    let stderr: String
    let stdoutTruncated: Bool
    let stderrTruncated: Bool
    let outputCaptureLimitBytes: Int
    let outputCaptureEnabled: Bool
    let outputEmpty: Bool
    let timeoutSeconds: Int?
    let processID: Int?
    let terminationStatus: String?

    enum CodingKeys: String, CodingKey {
        case stdout
        case stderr
        case stdoutTruncated = "stdout_truncated"
        case stderrTruncated = "stderr_truncated"
        case outputCaptureLimitBytes = "output_capture_limit_bytes"
        case outputCaptureEnabled = "output_capture_enabled"
        case outputEmpty = "output_empty"
        case timeoutSeconds = "timeout_seconds"
        case processID = "process_id"
        case terminationStatus = "termination_status"
    }
}

struct HeadlessContextBuilderRunSnapshot: Codable, Equatable {
    struct Meta: Codable, Equatable {
        let waitResult: String?

        enum CodingKeys: String, CodingKey {
            case waitResult = "wait_result"
        }
    }

    let contextID: String
    let runStatus: String
    let statusText: String
    let startedAt: String?
    let updatedAt: String
    let elapsedSeconds: Int?
    let agent: String
    let responseType: String
    let processID: Int?
    let resultStatus: String?
    let error: String?
    let nextAction: String?
    let diagnostics: HeadlessContextBuilderDiagnostics?
    let meta: Meta?

    enum CodingKeys: String, CodingKey {
        case contextID = "context_id"
        case runStatus = "run_status"
        case statusText = "status_text"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case elapsedSeconds = "elapsed_seconds"
        case agent
        case responseType = "response_type"
        case processID = "process_id"
        case resultStatus = "result_status"
        case error
        case nextAction = "next_action"
        case diagnostics
        case meta = "_meta"
    }
}

struct HeadlessContextBuilderCleanupReply: Codable, Equatable {
    struct CleanupContext: Codable, Equatable {
        let contextID: String
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case contextID = "context_id"
            case reason
        }
    }

    let status: String
    let deletedCount: Int
    let skippedCount: Int
    let deletedContexts: [CleanupContext]
    let skippedContexts: [CleanupContext]

    enum CodingKeys: String, CodingKey {
        case status
        case deletedCount = "deleted_count"
        case skippedCount = "skipped_count"
        case deletedContexts = "deleted_contexts"
        case skippedContexts = "skipped_contexts"
    }
}

enum HeadlessJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func string(_ value: some Encodable) throws -> String {
        try String(data: encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}

extension MCP.Value {
    var stringArray: [String]? {
        arrayValue?.compactMap(\.stringValue)
    }

    var stringObject: [String: MCP.Value]? {
        objectValue
    }

    func intCoerced() -> Int? {
        intValue ?? stringValue.flatMap(Int.init)
    }

    func boolCoerced() -> Bool? {
        if let boolValue { return boolValue }
        guard let stringValue else { return nil }
        switch stringValue.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension [String] {
    func nonEmptyTrimmed() -> [String] {
        compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

func jsonTextResult(_ value: some Codable) throws -> CallTool.Result {
    try CallTool.Result(
        content: [.text(text: HeadlessJSON.string(value), annotations: nil, _meta: nil)],
        structuredContent: value,
        isError: false
    )
}

func startHeadlessSocketListener(
    path: String,
    host: HeadlessWorkspaceHost,
    label: String = "socket connection"
) throws -> HeadlessUnixSocketListener {
    let listener = HeadlessUnixSocketListener(path: path)
    try listener.start { [host] fd in
        do {
            try await HeadlessMCPServer(host: host).runSocketConnection(fd: fd)
        } catch {
            fputs("rpce-headless \(label): \(error.localizedDescription)\n", stderr)
        }
    }
    return listener
}

func currentHeadlessExecutablePath() throws -> String {
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
