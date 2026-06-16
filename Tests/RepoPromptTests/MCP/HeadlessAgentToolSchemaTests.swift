import Foundation
import MCP
@testable import RepoPromptHeadlessServer
import XCTest

final class HeadlessAgentToolSchemaTests: XCTestCase {
    func testFullHeadlessToolsAdvertiseAgentRunAndManageButDiscoveryToolsDoNot() throws {
        let expectedFullToolNames: Set<String> = [
            "headless_capabilities",
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
        XCTAssertEqual(fullToolNames.count, 12)

        XCTAssertTrue(fullToolNames.contains("agent_run"), "Full headless MCP tools should advertise agent_run.")
        XCTAssertTrue(fullToolNames.contains("agent_manage"), "Full headless MCP tools should advertise agent_manage.")
        XCTAssertFalse(fullToolNames.contains("agent_explore"), "Headless MCP should not advertise app/window-only agent_explore.")

        let discoveryToolNames = Set(HeadlessToolSchemas.discoveryTools.map(\.name))
        XCTAssertEqual(discoveryToolNames, HeadlessToolSchemas.discoveryToolNames)
        XCTAssertTrue(discoveryToolNames.contains("headless_capabilities"), "Discovery-restricted sockets should expose the read-only capabilities contract.")
        XCTAssertFalse(discoveryToolNames.contains("agent_run"), "Discovery-restricted headless sockets must not expose agent_run.")
        XCTAssertFalse(discoveryToolNames.contains("agent_manage"), "Discovery-restricted headless sockets must not expose agent_manage.")
        XCTAssertFalse(discoveryToolNames.contains("context_builder"), "Discovery-restricted headless sockets must not expose context_builder.")
        XCTAssertFalse(discoveryToolNames.contains("agent_explore"), "Discovery-restricted headless sockets must not expose agent_explore.")
    }

    func testHeadlessCapabilitiesMirrorToolExposure() throws {
        let capabilities = HeadlessCapabilities.make(loadedRoots: ["/tmp/example"])
        XCTAssertEqual(capabilities.loadedRoots, ["/tmp/example"])

        let stdio = try XCTUnwrap(capabilities.transports.first { $0.name == "stdio" })
        XCTAssertEqual(stdio.exposure, "full")
        XCTAssertEqual(stdio.tools, HeadlessToolSchemas.tools.map(\.name).sorted())

        let socket = try XCTUnwrap(capabilities.transports.first { $0.name == "socket" })
        XCTAssertEqual(socket.exposure, "discovery_restricted")
        XCTAssertEqual(socket.tools, HeadlessToolSchemas.discoveryToolNames.sorted())
        XCTAssertTrue(capabilities.recommendedWorkflow.contains { $0.contains("context_builder") })
        XCTAssertTrue(capabilities.agentRun.fakeAgentCaveat.contains("FAKE_AGENT_SCRIPT"))
        XCTAssertTrue(capabilities.exitCodes.contains { $0.code == 64 && $0.meaning.contains("usage") })
    }

    func testRobotDocsGuideNamesPreferredAgentWorkflow() {
        let guide = HeadlessCapabilities.robotDocsGuide(loadedRoots: ["/repo"])
        XCTAssertTrue(guide.contains("rpce-headless capabilities --json"))
        XCTAssertTrue(guide.contains("headless_capabilities"))
        XCTAssertTrue(guide.contains("agent_manage"))
        XCTAssertTrue(guide.contains("agent_run"))
        XCTAssertTrue(guide.contains("context_builder"))
        XCTAssertTrue(guide.contains("FAKE_AGENT_SCRIPT"))
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

    func testContextBuilderSchemaExposesAsyncLifecycleWithoutDiscoveryAccess() throws {
        XCTAssertEqual(
            try opEnumValues(forToolNamed: "context_builder"),
            ["start", "poll", "wait", "get_result", "cancel", "cleanup"]
        )

        let properties = try XCTUnwrap(try schemaJSON(for: tool(named: "context_builder"))["properties"] as? [String: Any])
        XCTAssertNotNil(properties["instructions"], "instructions remains available for one-shot/start calls.")
        XCTAssertNotNil(properties["context_id"], "context_id is advertised for lifecycle calls.")
        XCTAssertNotNil(properties["timeout"], "wait timeout is advertised for lifecycle calls.")
        XCTAssertEqual(try requiredFields(forToolNamed: "context_builder"), [])
        let branches = try contextBuilderSchemaBranches()
        XCTAssertEqual(branches.count, 3)
        XCTAssertEqual(branches[0]["required"] as? [String], ["instructions"])
        XCTAssertNotNil(branches[0]["not"])
        XCTAssertEqual(branches[1]["required"] as? [String], ["op", "instructions"])
        XCTAssertEqual(((branches[1]["properties"] as? [String: Any])?["op"] as? [String: Any])?["const"] as? String, "start")
        XCTAssertEqual(branches[2]["required"] as? [String], ["op", "context_id"])
        XCTAssertEqual(
            ((branches[2]["properties"] as? [String: Any])?["op"] as? [String: Any])?["enum"] as? [String],
            ["poll", "wait", "get_result", "cancel", "cleanup"]
        )
        XCTAssertFalse(HeadlessToolSchemas.discoveryToolNames.contains("context_builder"))
    }

    func testContextBuilderSchemaDescriptionsTeachAsyncLifecycle() throws {
        let toolDescription = try tool(named: "context_builder").description
        XCTAssertTrue(toolDescription.contains("Omit op"))
        XCTAssertTrue(toolDescription.contains("op=start"))
        XCTAssertTrue(toolDescription.contains("timeout_seconds"))

        let timeoutSeconds = try propertySchema(named: "timeout_seconds", forToolNamed: "context_builder")
        XCTAssertTrue((timeoutSeconds["description"] as? String)?.contains("Discovery-agent lifetime cap") == true)
        let waitTimeout = try propertySchema(named: "timeout", forToolNamed: "context_builder")
        XCTAssertTrue((waitTimeout["description"] as? String)?.contains("Client wait deadline") == true)
    }

    func testContextBuilderRequestParsingKeepsSynchronousCompatibilityMode() throws {
        let request = try HeadlessContextBuilderService.toolRequestFromMCP(arguments: [
            "instructions": .string("Map the headless server"),
            "response_type": .string("clarify")
        ], environment: ["RPCE_CONTEXT_BUILDER_AGENT": "fake"])

        XCTAssertEqual(request.operation, .synchronous)
        XCTAssertNil(request.contextID)
        XCTAssertEqual(request.request?.instructions, "Map the headless server")
        XCTAssertEqual(request.request?.agentName, "fake")
    }

    func testContextBuilderStartRequiresInstructions() {
        XCTAssertThrowsError(try HeadlessContextBuilderService.toolRequestFromMCP(arguments: [
            "op": .string("start")
        ], environment: [:])) { error in
            XCTAssertEqual((error as? HeadlessToolFailure)?.message, "missing instructions")
        }
    }

    func testContextBuilderLifecycleOpsRequireContextID() {
        for op in ["poll", "wait", "get_result", "cancel", "cleanup"] {
            XCTAssertThrowsError(try HeadlessContextBuilderService.toolRequestFromMCP(arguments: [
                "op": .string(op)
            ], environment: [:]), "op=\(op) should require context_id") { error in
                XCTAssertEqual((error as? HeadlessToolFailure)?.message, "context_id is required and must be a non-empty string.")
            }
        }
    }

    func testContextBuilderUnknownOpIsRejectedByParser() {
        XCTAssertThrowsError(try HeadlessContextBuilderService.toolRequestFromMCP(arguments: [
            "op": .string("bogus"),
            "instructions": .string("Map the headless server")
        ], environment: [:])) { error in
            XCTAssertEqual(
                (error as? HeadlessToolFailure)?.message,
                "Unsupported context_builder op 'bogus'. Use start, poll, wait, get_result, cancel, or cleanup."
            )
        }
    }

    func testContextBuilderWaitTimeoutParsingIsSeparateFromDiscoveryDeadline() throws {
        let request = try HeadlessContextBuilderService.toolRequestFromMCP(arguments: [
            "op": .string("wait"),
            "context_id": .string("ctx-123"),
            "timeout": .int(2),
            "timeout_seconds": .int(99)
        ], environment: [:])

        XCTAssertEqual(request.operation, .wait)
        XCTAssertEqual(request.contextID, "ctx-123")
        XCTAssertEqual(request.waitTimeoutSeconds, 2)
        XCTAssertNil(request.request)
    }

    func testContextBuilderWaitIgnoresTimeoutSecondsAsPollingTimeout() throws {
        let request = try HeadlessContextBuilderService.toolRequestFromMCP(arguments: [
            "op": .string("wait"),
            "context_id": .string("ctx-123"),
            "timeout_seconds": .int(2)
        ], environment: [:])

        XCTAssertEqual(request.operation, .wait)
        XCTAssertEqual(request.contextID, "ctx-123")
        XCTAssertEqual(request.waitTimeoutSeconds, 120)
        XCTAssertNil(request.request)
    }

    func testContextBuilderRunSnapshotEncodesOptionalDiagnostics() throws {
        let snapshot = HeadlessContextBuilderRunSnapshot(
            contextID: "ctx-timeout",
            runStatus: "failed",
            statusText: "context_builder discovery failed.",
            updatedAt: "2026-06-15T00:00:00.000Z",
            agent: "fake",
            responseType: "clarify",
            processID: 42,
            resultStatus: nil,
            error: "context_builder discovery timed out after 1 seconds",
            diagnostics: HeadlessContextBuilderDiagnostics(
                stdout: "CTX_STDOUT",
                stderr: "CTX_STDERR",
                stdoutTruncated: true,
                stderrTruncated: false,
                outputCaptureLimitBytes: 80,
                outputCaptureEnabled: true,
                outputEmpty: false,
                timeoutSeconds: 1,
                processID: 42,
                terminationStatus: "sigkill_requested_after_timeout"
            ),
            meta: .init(waitResult: "timed_out")
        )

        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let diagnostics = try XCTUnwrap(json["diagnostics"] as? [String: Any])

        XCTAssertEqual(json["context_id"] as? String, "ctx-timeout")
        XCTAssertEqual(json["run_status"] as? String, "failed")
        XCTAssertEqual(diagnostics["stdout"] as? String, "CTX_STDOUT")
        XCTAssertEqual(diagnostics["stderr"] as? String, "CTX_STDERR")
        XCTAssertEqual(diagnostics["stdout_truncated"] as? Bool, true)
        XCTAssertEqual(diagnostics["stderr_truncated"] as? Bool, false)
        XCTAssertEqual(diagnostics["output_capture_limit_bytes"] as? Int, 80)
        XCTAssertEqual(diagnostics["output_capture_enabled"] as? Bool, true)
        XCTAssertEqual(diagnostics["output_empty"] as? Bool, false)
        XCTAssertEqual(diagnostics["timeout_seconds"] as? Int, 1)
        XCTAssertEqual(diagnostics["process_id"] as? Int, 42)
        XCTAssertEqual(diagnostics["termination_status"] as? String, "sigkill_requested_after_timeout")
        XCTAssertEqual((json["_meta"] as? [String: Any])?["wait_result"] as? String, "timed_out")
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

    private func contextBuilderSchemaBranches() throws -> [[String: Any]] {
        let schema = try schemaJSON(for: tool(named: "context_builder"))
        return try XCTUnwrap(schema["oneOf"] as? [[String: Any]])
    }

    private func schemaJSON(for tool: Tool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(tool.inputSchema)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func tool(named name: String) throws -> Tool {
        try XCTUnwrap(HeadlessToolSchemas.tools.first { $0.name == name })
    }
}
