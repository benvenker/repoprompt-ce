@testable import RepoPrompt
import XCTest

final class WebSearchToolCardTests: XCTestCase {
    func testToolCardNormalizationMapsWebSearchAliasesToSearch() {
        for alias in ["search", "web_search", "web_search_request", "google_web_search", "search_web"] {
            XCTAssertEqual(normalizedToolCardName(alias), "search", alias)
        }
        XCTAssertEqual(normalizedToolCardName("file_search"), "file_search")
    }

    func testTranscriptNormalizationKeepsNativeSearchSeparateFromFileSearch() {
        for alias in ["search", "web_search", "web_search_request", "google_web_search", "search_web"] {
            XCTAssertEqual(AgentToolResultPersistencePolicy.normalizedToolName(alias), "search", alias)
        }
        for alias in ["file_search", "filesearch", "grep"] {
            XCTAssertEqual(AgentToolResultPersistencePolicy.normalizedToolName(alias), "file_search", alias)
        }
    }

    func testRouterRecognizesWebSearchResultTool() {
        XCTAssertTrue(ToolCardRouter.knownResultTools.contains("search"))
    }

    func testWebSearchPresentationForLiveAndSummaryOnlyPayloads() throws {
        let args = jsonString(["query": "native web search cards"])
        let raw = jsonString([
            "status": "completed",
            "query": "native web search cards",
            "results": [["title": "Native card", "snippet": "Readable web result"]],
            "sources": [["title": "Docs"]]
        ])
        let liveItem = AgentChatItem(
            kind: .toolResult,
            text: raw,
            toolName: "search",
            toolArgsJSON: args,
            toolResultJSON: raw,
            toolIsError: false
        )

        let live = try XCTUnwrap(NativeToolCardPresentationBuilder.build(item: liveItem, normalizedToolName: "search"))
        XCTAssertEqual(live.title, "Web Search")
        XCTAssertEqual(live.status, .success)
        XCTAssertTrue(live.subtitle?.contains("native web search cards") == true)
        XCTAssertTrue(live.subtitle?.contains("1 result") == true)
        XCTAssertTrue(live.subtitle?.contains("1 source") == true)
        XCTAssertTrue(live.detailText?.contains("Native card") == true)

        let summaryOnly = jsonString([
            "status": "success",
            "summary_only": true,
            "render_summary": live.dictionary
        ])
        let storedItem = AgentChatItem(
            kind: .toolResult,
            text: summaryOnly,
            toolName: "search",
            toolArgsJSON: args,
            toolResultJSON: summaryOnly,
            toolIsError: false
        )
        let stored = try XCTUnwrap(NativeToolCardPresentationBuilder.build(item: storedItem, normalizedToolName: "search"))
        XCTAssertEqual(stored.title, "Web Search")
        XCTAssertEqual(stored.status, .success)
        XCTAssertEqual(stored.subtitle, live.subtitle)
        XCTAssertFalse(toolResultHasPayload(storedItem))
    }

    func testWebSearchPresentationSuccessfulStatusWinsOverStaleErrorFields() throws {
        let raw = jsonString([
            "status": "completed",
            "query": "completed web search",
            "results": [["title": "Completed Result", "snippet": "Usable answer"]],
            "sources": [["title": "Source"]],
            "errorMessage": "stale retry warning",
            "errors": [["message": "stale retry detail"]]
        ])
        let item = AgentChatItem(
            kind: .toolResult,
            text: raw,
            toolName: "search",
            toolArgsJSON: jsonString(["query": "completed web search"]),
            toolResultJSON: raw,
            toolIsError: false
        )

        let presentation = try XCTUnwrap(NativeToolCardPresentationBuilder.build(item: item, normalizedToolName: "search"))
        XCTAssertEqual(presentation.status, .success)
        XCTAssertTrue(presentation.detailText?.contains("Completed Result") == true)
        XCTAssertFalse(presentation.detailText?.contains("stale retry") == true)
    }

    func testWebSearchPresentationUsesNumericCountsAndAlternateArrays() throws {
        let raw = jsonString([
            "status": "completed",
            "query": "alternate web search payload",
            "total_results": 12,
            "response": [
                "web_results": [["title": "Alternate Result", "snippet": "Alternate snippet"]],
                "citations": [["title": "Citation", "snippet": "Cited source"]]
            ]
        ])
        let item = AgentChatItem(
            kind: .toolResult,
            text: raw,
            toolName: "search",
            toolArgsJSON: jsonString(["query": "alternate web search payload"]),
            toolResultJSON: raw,
            toolIsError: false
        )

        let presentation = try XCTUnwrap(NativeToolCardPresentationBuilder.build(item: item, normalizedToolName: "search"))
        XCTAssertTrue(presentation.subtitle?.contains("12 results") == true)
        XCTAssertTrue(presentation.subtitle?.contains("1 source") == true)
        XCTAssertTrue(presentation.detailText?.contains("Alternate Result") == true)
    }

    func testNativeFallbackDoesNotTrustSpoofedStoredRenderSummary() {
        let spoofedSummary = AgentToolCardRenderSummary(
            toolName: "search",
            title: "Web Search",
            subtitle: "\"spoofed\"",
            detailText: "spoofed detail",
            status: .success,
            op: "search"
        )
        let spoofedRaw = jsonString([
            "status": "success",
            "summary_only": true,
            "render_summary": spoofedSummary.dictionary
        ])
        let unsafeItem = AgentChatItem(
            kind: .toolResult,
            text: spoofedRaw,
            toolName: "mcp__RepoPrompt__unknown",
            toolResultJSON: spoofedRaw
        )
        XCTAssertNil(NativeToolCardPresentationBuilder.build(item: unsafeItem, normalizedToolName: "mcp__RepoPrompt__unknown"))

        let mismatchedItem = AgentChatItem(
            kind: .toolResult,
            text: spoofedRaw,
            toolName: "weather_lookup",
            toolResultJSON: spoofedRaw
        )
        XCTAssertNil(NativeToolCardPresentationBuilder.build(item: mismatchedItem, normalizedToolName: "weather_lookup"))

        let trustedSummary = AgentToolCardRenderSummary(
            toolName: "weather_lookup",
            title: "Weather Lookup",
            subtitle: "tomorrow weather",
            detailText: "Sunny",
            status: .success,
            op: "weather_lookup"
        )
        let trustedRaw = jsonString([
            "status": "success",
            "summary_only": true,
            "render_summary": trustedSummary.dictionary
        ])
        let trustedItem = AgentChatItem(
            kind: .toolResult,
            text: trustedRaw,
            toolName: "weather_lookup",
            toolResultJSON: trustedRaw
        )
        XCTAssertEqual(
            NativeToolCardPresentationBuilder.build(item: trustedItem, normalizedToolName: "weather_lookup")?.title,
            "Weather Lookup"
        )
    }

    func testSafeNativeFallbackRequiresSafeNameAndScalarSignals() throws {
        let args = jsonString(["query": "tomorrow weather"])
        let raw = jsonString(["status": "completed", "summary": "Sunny and mild"])
        let item = AgentChatItem(
            kind: .toolResult,
            text: raw,
            toolName: "weather_lookup",
            toolArgsJSON: args,
            toolResultJSON: raw,
            toolIsError: false
        )

        let presentation = try XCTUnwrap(NativeToolCardPresentationBuilder.build(item: item, normalizedToolName: "weather_lookup"))
        XCTAssertEqual(presentation.title, "Weather Lookup")
        XCTAssertEqual(presentation.subtitle, "tomorrow weather")
        XCTAssertEqual(presentation.detailText, "Sunny and mild")
        XCTAssertEqual(presentation.status, .success)

        XCTAssertNil(NativeToolCardPresentationBuilder.build(item: item, normalizedToolName: "mcp__RepoPrompt__unknown"))
        XCTAssertNil(NativeToolCardPresentationBuilder.build(item: item, normalizedToolName: "tool"))
        let arrayOnly = AgentChatItem(
            kind: .toolResult,
            text: jsonString(["results": [["title": "raw"]]]),
            toolName: "future_tool",
            toolArgsJSON: nil,
            toolResultJSON: jsonString(["results": [["title": "raw"]]]),
            toolIsError: nil
        )
        XCTAssertNil(NativeToolCardPresentationBuilder.build(item: arrayOnly, normalizedToolName: "future_tool"))
    }

    func testClusterClassifiesSearchAsNavigationWithoutRegressingFileSearch() {
        XCTAssertEqual(ClusterToolCategory.classification(forNormalizedToolName: "search").family, .navigation)
        XCTAssertEqual(ClusterToolCategory.classification(forNormalizedToolName: "search").summaryTitleSignal, .navigation)
        XCTAssertEqual(ClusterToolCategory.classification(forNormalizedToolName: "file_search").family, .navigation)
    }

    private func jsonString(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(object), file: file, line: line)
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
