import Foundation
import MCP
@testable import RepoPromptHeadlessServer
import XCTest

final class HeadlessWorkspaceHostTests: XCTestCase {
    func testCodeStructureFallbackNamesSearchAndReadFile() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "plain notes without a codemap\n".write(
            to: root.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let host = try await HeadlessWorkspaceHost(rootPaths: [root.path])
        let reply = try await host.codeStructure(paths: ["notes.txt"], scope: "paths", maxResults: 10)

        XCTAssertEqual(reply.requestedPaths, ["notes.txt"])
        XCTAssertEqual(reply.structureCount, 0)
        XCTAssertEqual(reply.files.count, 1)
        XCTAssertEqual(reply.files.first?.path, "notes.txt")
        XCTAssertEqual(reply.files.first?.status, "codemap_unavailable")
        XCTAssertEqual(reply.files.first?.hasStructure, false)
        XCTAssertEqual(reply.files.first?.fallbackTools, ["file_search", "read_file"])
        XCTAssertTrue(reply.text.contains("notes.txt"), reply.text)
        XCTAssertTrue(reply.text.contains("file_search"), reply.text)
        XCTAssertTrue(reply.text.contains("read_file"), reply.text)
    }

    func testWorkspaceContextStructuredReplyIncludesLoadedRoots() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "hello\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let host = try await HeadlessWorkspaceHost(rootPaths: [root.path])
        let reply = try await host.workspaceContext(args: ["include": .array([.string("tokens")])])

        XCTAssertEqual(reply.loadedRoots, [root.path])
        XCTAssertEqual(reply.loadedRootMetadata.map(\.path), [root.path])
        XCTAssertEqual(reply.loadedRootMetadata.map(\.name), [root.lastPathComponent])
    }

    func testDumpSummaryStructuredReplyIncludesRootMetadataAndWarnings() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "hello\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let host = try await HeadlessWorkspaceHost(rootPaths: [root.path])
        let reply = await host.dumpSummaryReply()

        XCTAssertEqual(reply.loadedRoots, [root.path])
        XCTAssertEqual(reply.loadedRootMetadata.map(\.path), [root.path])
        XCTAssertFalse(reply.currentDirectory.isEmpty)
        XCTAssertGreaterThanOrEqual(reply.rootCount, 1)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpce-headless-host-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.standardizedFileURL
    }
}
