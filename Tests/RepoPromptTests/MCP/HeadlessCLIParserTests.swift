import Foundation
@testable import RepoPromptHeadlessServer
import XCTest

final class HeadlessCLIParserTests: XCTestCase {
    func testTopLevelHelpIsFirstTryFriendly() throws {
        for args in [[], ["--help"], ["-h"], ["help"]] {
            let command = try HeadlessCLI.parse(args)
            guard case let .help(text) = command else {
                return XCTFail("Expected help for args \(args)")
            }
            XCTAssertTrue(text.contains("Usage: rpce-headless <command> [options]"))
            XCTAssertTrue(text.contains("robot-docs status --json"))
            XCTAssertTrue(text.contains("capabilities --json"))
            XCTAssertTrue(text.contains("robot-docs guide"))
        }
    }

    func testSubcommandHelpIsFirstTryFriendly() throws {
        for subcommand in ["serve", "dump", "connect", "context-build", "capabilities", "robot-docs"] {
            let command = try HeadlessCLI.parse([subcommand, "--help"])
            guard case let .help(text) = command else {
                return XCTFail("Expected help for \(subcommand)")
            }
            XCTAssertTrue(text.contains("Usage: rpce-headless \(subcommand)"), text)
        }
    }

    func testCapabilitiesAcceptsJsonFlag() throws {
        let command = try HeadlessCLI.parse(["capabilities", "--json"])
        guard case .capabilities = command else {
            return XCTFail("Expected capabilities command")
        }
    }

    func testRobotDocsGuideCommand() throws {
        let command = try HeadlessCLI.parse(["robot-docs", "guide"])
        guard case .robotDocsGuide = command else {
            return XCTFail("Expected robot docs guide command")
        }
    }

    func testRobotDocsStatusJsonCommand() throws {
        let command = try HeadlessCLI.parse(["robot-docs", "status", "--json"])
        guard case .robotDocsStatus = command else {
            return XCTFail("Expected robot docs status command")
        }
    }

    func testRobotDocsTriageJsonAlias() throws {
        let command = try HeadlessCLI.parse(["robot-docs", "triage", "--json"])
        guard case .robotDocsStatus = command else {
            return XCTFail("Expected robot docs triage alias to parse as status")
        }
    }

    func testRobotDocsStatusRequiresJsonAndTeachesCommand() {
        XCTAssertThrowsError(try HeadlessCLI.parse(["robot-docs", "status"])) { error in
            let exit = error as? HeadlessCLI.ExitError
            XCTAssertEqual(exit?.code, 64)
            XCTAssertTrue(exit?.message.contains("rpce-headless robot-docs status --json") == true, exit?.message ?? "")
        }
    }

    func testDumpJsonCommand() throws {
        let command = try HeadlessCLI.parse(["dump", "--json"])
        guard case let .dump(_, json) = command else {
            return XCTFail("Expected dump command")
        }
        XCTAssertTrue(json)
    }

    func testUnknownJsonTypoTeachesCorrection() throws {
        XCTAssertThrowsError(try HeadlessCLI.parse(["dump", "--jsno"])) { error in
            let exit = error as? HeadlessCLI.ExitError
            XCTAssertEqual(exit?.code, 64)
            XCTAssertTrue(exit?.message.contains("Did you mean `--json`?") == true, exit?.message ?? "")
        }
    }
}
