import Foundation
import XCTest

final class HeadlessAgentToolSchemaTests: XCTestCase {
    func testFullHeadlessToolsAdvertiseAgentRunAndManageButDiscoveryToolsDoNot() throws {
        let source = try Self.headlessToolSchemasSource()
        let fullToolNames = Self.toolNames(inFullToolsSource: source)
        let discoveryToolNames = try Self.discoveryToolNames(in: source)

        for existingTool in [
            "read_file",
            "get_file_tree",
            "file_search",
            "get_code_structure",
            "manage_selection",
            "workspace_context",
            "prompt",
            "oracle_send"
        ] {
            XCTAssertTrue(fullToolNames.contains(existingTool), "Headless full MCP tools should continue to include \(existingTool).")
        }

        XCTAssertTrue(fullToolNames.contains("agent_run"), "Full headless MCP tools should advertise agent_run.")
        XCTAssertTrue(fullToolNames.contains("agent_manage"), "Full headless MCP tools should advertise agent_manage.")
        XCTAssertFalse(fullToolNames.contains("agent_explore"), "Headless MCP should not advertise app/window-only agent_explore.")

        XCTAssertFalse(discoveryToolNames.contains("agent_run"), "Discovery-restricted headless sockets must not expose agent_run.")
        XCTAssertFalse(discoveryToolNames.contains("agent_manage"), "Discovery-restricted headless sockets must not expose agent_manage.")
        XCTAssertFalse(discoveryToolNames.contains("agent_explore"), "Discovery-restricted headless sockets must not expose agent_explore.")
    }

    func testHeadlessAgentOpEnumsAreScopedToProcessBackedSubset() throws {
        let source = try Self.headlessToolSchemasSource()

        XCTAssertEqual(
            try Self.opEnumValues(forToolNamed: "agent_run", in: source),
            ["start", "poll", "wait", "cancel"],
            "Headless agent_run should expose only the planned process-backed lifecycle ops."
        )
        XCTAssertEqual(
            try Self.opEnumValues(forToolNamed: "agent_manage", in: source),
            ["list_agents", "list_sessions", "get_log", "stop_session", "cleanup_sessions"],
            "Headless agent_manage should expose only the planned process-backed management ops."
        )
    }

    private static func headlessToolSchemasSource() throws -> String {
        let relativePath = "Sources/RepoPromptHeadlessServer/HeadlessToolSchemas.swift"
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0 ..< 6 {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate \(relativePath) from test working directory")
    }

    private static func toolNames(inFullToolsSource source: String) -> Set<String> {
        Set(matches(in: source, pattern: #"Tool\(\s*name:\s*\"([^\"]+)\""#))
    }

    private static func discoveryToolNames(in source: String) throws -> Set<String> {
        guard let markerRange = source.range(of: "static let discoveryToolNames: Set<String> = [") else {
            XCTFail("Could not find HeadlessToolSchemas.discoveryToolNames")
            return []
        }
        let afterMarker = source[markerRange.upperBound...]
        guard let closeRange = afterMarker.range(of: "]") else {
            XCTFail("Could not find end of HeadlessToolSchemas.discoveryToolNames")
            return []
        }
        return Set(matches(in: String(afterMarker[..<closeRange.lowerBound]), pattern: #"\"([^\"]+)\""#))
    }

    private static func opEnumValues(forToolNamed toolName: String, in source: String) throws -> [String] {
        guard let toolNameRange = source.range(of: #"name:\s*\"\#(toolName)\""#, options: .regularExpression) else {
            XCTFail("Could not find headless tool schema for \(toolName)")
            return []
        }
        let afterToolName = source[toolNameRange.upperBound...]
        let nextToolRange = afterToolName.range(of: #"\n\s*Tool\("#, options: .regularExpression)
        let toolSource = String(nextToolRange.map { afterToolName[..<$0.lowerBound] } ?? afterToolName)
        guard let opPropertyRange = toolSource.range(of: #"\"op\"\s*:\s*string\([^\n]+enumValues:\s*\[(.*?)\]\)"#, options: .regularExpression) else {
            XCTFail("Could not find op enum for headless tool schema \(toolName)")
            return []
        }
        return matches(in: String(toolSource[opPropertyRange]), pattern: #"\"([^\"]+)\""#)
            .filter { $0 != "op" }
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            XCTFail("Invalid regex pattern: \(pattern)")
            return []
        }
        let nsRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}
