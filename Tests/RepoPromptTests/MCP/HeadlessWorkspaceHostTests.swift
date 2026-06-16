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
        let text = try await host.codeStructure(paths: ["notes.txt"], scope: "paths", maxResults: 10)

        XCTAssertTrue(text.contains("notes.txt"), text)
        XCTAssertTrue(text.contains("file_search"), text)
        XCTAssertTrue(text.contains("read_file"), text)
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
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpce-headless-host-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.standardizedFileURL
    }
}
