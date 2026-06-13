import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

struct OracleConfig {
    let baseURL: String
    let apiKey: String
    let defaultModel: String

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> OracleConfig {
        let baseURL = environment.trimmed("RPCE_ORACLE_BASE_URL") ?? "https://openrouter.ai/api/v1"
        guard let apiKey = environment.trimmed("RPCE_ORACLE_API_KEY") ?? environment.trimmed("OPENROUTER_API_KEY") else {
            throw OracleClientError.missingAPIKey
        }
        return OracleConfig(
            baseURL: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            apiKey: apiKey,
            defaultModel: environment.trimmed("RPCE_ORACLE_MODEL") ?? "openrouter/auto"
        )
    }
}

struct ChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

actor OpenAICompatibleClient {
    private let client: HTTPClient
    private var isShutDown = false

    init() {
        client = HTTPClient(eventLoopGroupProvider: .singleton)
    }

    func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        try? await client.shutdown()
    }

    func streamChat(messages: [ChatMessage], model: String, config: OracleConfig) -> AsyncThrowingStream<String, Error> {
        let httpClient = client
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = HTTPClientRequest(url: "\(config.baseURL)/chat/completions")
                    request.method = .POST
                    request.headers.add(name: "Authorization", value: "Bearer \(config.apiKey)")
                    request.headers.add(name: "Content-Type", value: "application/json")
                    let requestData = try JSONEncoder().encode(ChatCompletionRequest(model: model, messages: messages, stream: true))
                    request.body = .bytes(ByteBuffer(bytes: requestData))

                    let response = try await httpClient.execute(request, timeout: .seconds(600))
                    guard (200 ..< 300).contains(Int(response.status.code)) else {
                        let prefix = try await Self.bodyPrefix(response.body, limit: 500)
                        throw OracleClientError.httpStatus(Int(response.status.code), prefix)
                    }

                    var lineBuffer = ""
                    for try await var chunk in response.body {
                        guard let text = chunk.readString(length: chunk.readableBytes), !text.isEmpty else { continue }
                        lineBuffer.append(text)
                        while let newline = lineBuffer.firstIndex(of: "\n") {
                            let rawLine = String(lineBuffer[..<newline])
                            lineBuffer.removeSubrange(...newline)
                            try Self.processServerSentEventLine(rawLine, continuation: continuation)
                        }
                    }
                    if !lineBuffer.isEmpty {
                        try Self.processServerSentEventLine(lineBuffer, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func processServerSentEventLine(_ rawLine: String, continuation: AsyncThrowingStream<String, Error>.Continuation) throws {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix(":") else { return }
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]" else {
            continuation.finish()
            return
        }
        guard let data = payload.data(using: .utf8) else { return }
        let event = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
        if let content = event.choices.first?.delta.content, !content.isEmpty {
            continuation.yield(content)
        }
    }

    private static func bodyPrefix(_ body: HTTPClientResponse.Body, limit: Int) async throws -> String {
        var data = Data()
        for try await var chunk in body {
            if let bytes = chunk.readBytes(length: min(chunk.readableBytes, max(0, limit - data.count))) {
                data.append(contentsOf: bytes)
            }
            if data.count >= limit { break }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum OracleClientError: Error, LocalizedError {
    case missingAPIKey
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "oracle_send requires RPCE_ORACLE_API_KEY or OPENROUTER_API_KEY"
        case let .httpStatus(status, body):
            body.isEmpty ? "oracle endpoint returned HTTP \(status)" : "oracle endpoint returned HTTP \(status): \(body)"
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}

private extension [String: String] {
    func trimmed(_ key: String) -> String? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
