import Foundation
import MCP
@testable import RepoPromptHeadlessServer
import XCTest

final class HeadlessAgentToolSchemaTests: XCTestCase {
    func testFullHeadlessToolsAdvertiseAgentRunAndManageButDiscoveryToolsDoNot() throws {
        let expectedFullToolNames: Set<String> = [
            "read_file",
            "get_file_tree",
            "file_search",
            "get_code_structure",
            "manage_selection",
            "workspace_context",
            "prompt",
            "agent_run",
            "agent_manage",
            "context_builder",
            "oracle_send"
        ]
        let fullToolNames = Set(HeadlessToolSchemas.tools.map(\.name))

        XCTAssertEqual(fullToolNames, expectedFullToolNames)
        XCTAssertEqual(fullToolNames.count, 11)

        XCTAssertTrue(fullToolNames.contains("agent_run"), "Full headless MCP tools should advertise agent_run.")
        XCTAssertTrue(fullToolNames.contains("agent_manage"), "Full headless MCP tools should advertise agent_manage.")
        XCTAssertFalse(fullToolNames.contains("agent_explore"), "Headless MCP should not advertise app/window-only agent_explore.")

        let discoveryToolNames = Set(HeadlessToolSchemas.discoveryTools.map(\.name))
        XCTAssertEqual(discoveryToolNames, HeadlessToolSchemas.discoveryToolNames)
        XCTAssertFalse(discoveryToolNames.contains("agent_run"), "Discovery-restricted headless sockets must not expose agent_run.")
        XCTAssertFalse(discoveryToolNames.contains("agent_manage"), "Discovery-restricted headless sockets must not expose agent_manage.")
        XCTAssertFalse(discoveryToolNames.contains("agent_explore"), "Discovery-restricted headless sockets must not expose agent_explore.")
    }

    func testHeadlessAgentOpEnumsAreScopedToProcessBackedSubset() throws {
        XCTAssertEqual(
            try opEnumValues(forToolNamed: "agent_run"),
            ["start", "poll", "wait", "cancel"],
            "Headless agent_run should expose only the planned process-backed lifecycle ops."
        )
        XCTAssertEqual(
            try opEnumValues(forToolNamed: "agent_manage"),
            ["list_agents", "list_sessions", "get_log", "stop_session", "cleanup_sessions"],
            "Headless agent_manage should expose only the planned process-backed management ops."
        )
    }

    func testHeadlessAgentOpIsRequiredInSchemas() throws {
        XCTAssertEqual(try requiredFields(forToolNamed: "agent_run"), ["op"])
        XCTAssertEqual(try requiredFields(forToolNamed: "agent_manage"), ["op"])
    }

    private func opEnumValues(forToolNamed toolName: String) throws -> [String] {
        let opSchema = try propertySchema(named: "op", forToolNamed: toolName)
        return try XCTUnwrap(opSchema["enum"] as? [String])
    }

    private func requiredFields(forToolNamed toolName: String) throws -> [String] {
        let schema = try schemaJSON(for: tool(named: toolName))
        return try XCTUnwrap(schema["required"] as? [String])
    }

    private func propertySchema(named propertyName: String, forToolNamed toolName: String) throws -> [String: Any] {
        let schema = try schemaJSON(for: tool(named: toolName))
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        return try XCTUnwrap(properties[propertyName] as? [String: Any])
    }

    private func schemaJSON(for tool: Tool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(tool.inputSchema)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func tool(named name: String) throws -> Tool {
        try XCTUnwrap(HeadlessToolSchemas.tools.first { $0.name == name })
    }
}
