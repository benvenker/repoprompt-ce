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
        case selectedFiles = "selected_files"
        case codemapFiles = "codemap_files"
        case totalTokens = "total_tokens"
        case fileTokens = "file_tokens"
        case fileTreeTokens = "file_tree_tokens"
        case missingPaths = "missing_paths"
        case invalidPaths = "invalid_paths"
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
    let updatedAt: String
    let agent: String
    let responseType: String
    let processID: Int?
    let resultStatus: String?
    let error: String?
    let diagnostics: HeadlessContextBuilderDiagnostics?
    let meta: Meta?

    enum CodingKeys: String, CodingKey {
        case contextID = "context_id"
        case runStatus = "run_status"
        case statusText = "status_text"
        case updatedAt = "updated_at"
        case agent
        case responseType = "response_type"
        case processID = "process_id"
        case resultStatus = "result_status"
        case error
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

extension [String] {
    func nonEmptyTrimmed() -> [String] {
        compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
