import Foundation
import MCP
import RepoPromptContextCore

struct HeadlessToolFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
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

enum HeadlessJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func string<T: Encodable>(_ value: T) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}

extension MCP.Value {
    var stringArray: [String]? { arrayValue?.compactMap(\.stringValue) }

    var stringObject: [String: MCP.Value]? { objectValue }

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

extension Array where Element == String {
    func nonEmptyTrimmed() -> [String] {
        compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
