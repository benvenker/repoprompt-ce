import Foundation
import MCP

actor OracleService {
    private let host: HeadlessWorkspaceHost
    private let client: OpenAICompatibleClient
    private let fileManager: FileManager
    private let chatsDirectory: URL

    init(host: HeadlessWorkspaceHost, client: OpenAICompatibleClient = OpenAICompatibleClient(), fileManager: FileManager = .default) {
        self.host = host
        self.client = client
        self.fileManager = fileManager
        chatsDirectory = Self.defaultStateDirectory(fileManager: fileManager).appendingPathComponent("chats", isDirectory: true)
    }

    func shutdown() async {
        await client.shutdown()
    }

    func send(message: String, chatID: String?, model: String?, includeContext: Bool) async throws -> (chatID: String, model: String, stream: AsyncThrowingStream<String, Error>) {
        let config = try OracleConfig.fromEnvironment()
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw HeadlessToolFailure(message: "message must not be empty") }

        var session = try loadOrCreateSession(chatID: chatID, defaultModel: config.defaultModel)
        let resolvedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? session.model
        session.model = resolvedModel

        var outbound: [ChatMessage] = [ChatMessage(role: "system", content: Self.systemPrompt)]
        if includeContext {
            let context = try await host.workspaceContext(args: [:]).context
            outbound.append(ChatMessage(role: "user", content: "Repository context:\n\n\(context)"))
        }
        outbound.append(contentsOf: session.messages)
        let userMessage = ChatMessage(role: "user", content: trimmedMessage)
        outbound.append(userMessage)
        session.messages.append(userMessage)

        let upstream = await client.streamChat(messages: outbound, model: resolvedModel, config: config)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                var assistantReply = ""
                do {
                    for try await delta in upstream {
                        assistantReply += delta
                        continuation.yield(delta)
                    }
                    session.messages.append(ChatMessage(role: "assistant", content: assistantReply))
                    try self.save(session)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (session.id, resolvedModel, stream)
    }

    private func loadOrCreateSession(chatID: String?, defaultModel: String) throws -> OracleChatSession {
        try fileManager.createDirectory(at: chatsDirectory, withIntermediateDirectories: true)
        guard let chatID = chatID?.trimmingCharacters(in: .whitespacesAndNewlines), !chatID.isEmpty else {
            return OracleChatSession(id: UUID().uuidString, createdAt: Date(), model: defaultModel, messages: [])
        }
        let url = sessionURL(chatID)
        guard fileManager.fileExists(atPath: url.path) else {
            return OracleChatSession(id: chatID, createdAt: Date(), model: defaultModel, messages: [])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OracleChatSession.self, from: data)
    }

    private func save(_ session: OracleChatSession) throws {
        try fileManager.createDirectory(at: chatsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(session)
        try data.write(to: sessionURL(session.id), options: [.atomic])
    }

    private func sessionURL(_ chatID: String) -> URL {
        chatsDirectory.appendingPathComponent(safeChatID(chatID)).appendingPathExtension("json")
    }

    private func safeChatID(_ chatID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let characters = chatID.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        let value = String(characters).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return value.isEmpty ? UUID().uuidString : value
    }

    private static let systemPrompt = """
    You are a senior engineer answering over the provided repository context.
    Be precise, concise, and cite relevant paths when useful.
    Do not claim access to files or tools beyond the supplied context.
    """

    private static func defaultStateDirectory(fileManager: FileManager) -> URL {
        let environment = ProcessInfo.processInfo.environment
        #if os(macOS)
            if let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                return applicationSupport.appendingPathComponent("rpce-headless", isDirectory: true)
            }
        #endif
        if let xdgState = environment["XDG_STATE_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !xdgState.isEmpty {
            return URL(fileURLWithPath: xdgState).appendingPathComponent("rpce-headless", isDirectory: true)
        }
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? fileManager.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: home).appendingPathComponent(".local/state/rpce-headless", isDirectory: true)
    }
}

struct OracleChatSession: Codable, Equatable {
    let id: String
    let createdAt: Date
    var model: String
    var messages: [ChatMessage]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
