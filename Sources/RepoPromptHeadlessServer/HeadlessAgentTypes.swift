import Foundation

struct HeadlessAgentRuntimeConfiguration {
    let agentConfigPath: String?
    let defaultAgentName: String
    let socketDirectory: URL?
    let outputCaptureLimitBytes: Int

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> HeadlessAgentRuntimeConfiguration {
        HeadlessAgentRuntimeConfiguration(
            agentConfigPath: environment.headlessTrimmed("RPCE_AGENT_CONFIG"),
            defaultAgentName: environment.headlessTrimmed("RPCE_AGENT_RUN_DEFAULT_AGENT") ?? "claude",
            socketDirectory: environment.headlessTrimmed("RPCE_AGENT_SOCKET_DIRECTORY").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) },
            outputCaptureLimitBytes: environment.headlessTrimmedInt("RPCE_AGENT_OUTPUT_CAPTURE_LIMIT_BYTES") ?? 1_000_000
        )
    }
}

enum HeadlessAgentRunStatus: String, Codable {
    case running
    case completed
    case failed
    case cancelled
    case expired

    var isTerminal: Bool {
        self != .running
    }
}

struct HeadlessAgentRunSnapshot: Codable {
    struct Session: Codable {
        let id: String
        let name: String
    }

    struct Agent: Codable {
        let id: String
        let name: String
        let model: String
        let reasoningEffort: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case model
            case reasoningEffort = "reasoning_effort"
        }
    }

    struct Meta: Codable {
        let waitResult: String?

        enum CodingKeys: String, CodingKey {
            case waitResult = "wait_result"
        }
    }

    let sessionID: String
    let status: String
    let statusText: String
    let assistantText: String
    let transcriptItemCount: Int
    let updatedAt: String
    let session: Session
    let agent: Agent
    let meta: Meta?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case status
        case statusText = "status_text"
        case assistantText = "assistant_text"
        case transcriptItemCount = "transcript_item_count"
        case updatedAt = "updated_at"
        case session
        case agent
        case meta = "_meta"
    }
}

struct HeadlessAgentModelInfo: Codable {
    let modelID: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case name
    }
}

struct HeadlessAgentInfo: Codable {
    let name: String
    let available: Bool
    let models: [HeadlessAgentModelInfo]
}

struct HeadlessAgentListAgentsReply: Codable {
    let agents: [HeadlessAgentInfo]
}

struct HeadlessAgentSessionAgentSummary: Codable {
    let id: String
    let model: String
}

struct HeadlessAgentSessionSummary: Codable {
    let sessionID: String
    let name: String
    let lastModified: String
    let itemCount: Int
    let state: String
    let isLive: Bool
    let agent: HeadlessAgentSessionAgentSummary
    let isMCPOriginated: Bool

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case name
        case lastModified = "last_modified"
        case itemCount = "item_count"
        case state
        case isLive = "is_live"
        case agent
        case isMCPOriginated = "is_mcp_originated"
    }
}

struct HeadlessAgentListSessionsReply: Codable {
    let sessions: [HeadlessAgentSessionSummary]
}

struct HeadlessAgentLogReply: Codable {
    let sessionID: String
    let name: String
    let turnOffset: Int
    let turnLimit: Int
    let returnedTurnCount: Int
    let totalTurns: Int
    let transcriptXML: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case name
        case turnOffset = "turn_offset"
        case turnLimit = "turn_limit"
        case returnedTurnCount = "returned_turn_count"
        case totalTurns = "total_turns"
        case transcriptXML = "transcript_xml"
    }
}

struct HeadlessAgentStopSessionReply: Codable {
    let stopRequested: Bool
    let session: HeadlessAgentSessionSummary

    enum CodingKeys: String, CodingKey {
        case stopRequested = "stop_requested"
        case session
    }
}

struct HeadlessAgentCleanupReply: Codable {
    struct CleanupSession: Codable {
        let sessionID: String
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case reason
        }
    }

    let status: String
    let deletedCount: Int
    let skippedCount: Int
    let deletedSessions: [CleanupSession]
    let skippedSessions: [CleanupSession]

    enum CodingKeys: String, CodingKey {
        case status
        case deletedCount = "deleted_count"
        case skippedCount = "skipped_count"
        case deletedSessions = "deleted_sessions"
        case skippedSessions = "skipped_sessions"
    }
}

extension DateFormatter {
    static let headlessAgentISO8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}

extension [String: String] {
    func headlessTrimmed(_ key: String) -> String? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    func headlessTrimmedInt(_ key: String) -> Int? {
        headlessTrimmed(key).flatMap(Int.init)
    }
}
