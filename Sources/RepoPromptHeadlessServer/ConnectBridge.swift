import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

enum ConnectBridge {
    static func run(socketPath: String, auth: Bool) async throws {
        let token: String?
        if auth {
            let trimmedToken = ProcessInfo.processInfo.environment["RPCE_SOCKET_AUTH_TOKEN"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmedToken, !trimmedToken.isEmpty else {
                throw HeadlessCLI.ExitError(
                    code: 64,
                    message: "rpce-headless connect: missing RPCE_SOCKET_AUTH_TOKEN"
                )
            }
            token = trimmedToken
        } else {
            token = nil
        }

        let socketFD = try connectSocket(path: socketPath)
        defer { closeFD(socketFD) }

        if let token {
            try writeAuthRequest(token: token, to: socketFD)
            guard try await readAuthResponse(from: socketFD) == .accepted else {
                throw HeadlessCLI.ExitError(
                    code: 65,
                    message: "rpce-headless connect: socket authentication rejected"
                )
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try pump(inputFD: STDIN_FILENO, outputFD: socketFD)
                shutdown(socketFD, shutdownWriteValue)
            }
            group.addTask {
                try pump(inputFD: socketFD, outputFD: STDOUT_FILENO)
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private static func connectSocket(path: String) throws -> Int32 {
        guard path.utf8.count < MemoryLayout<sockaddr_un>.size - 2 else {
            throw HeadlessToolFailure(message: "socket path is too long: \(path)")
        }
        let fd = socket(AF_UNIX, streamSocketType, 0)
        guard fd >= 0 else { throw POSIXFailure(operation: "socket", code: errno) }

        var address = try makeUnixSocketAddress(path: path)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            closeFD(fd)
            throw POSIXFailure(operation: "connect", code: code)
        }
        return fd
    }

    private enum AuthResponse {
        case accepted
        case rejected
    }

    private struct AuthRequest: Encodable {
        let rpceAuth: Token

        enum CodingKeys: String, CodingKey {
            case rpceAuth = "rpce_auth"
        }
    }

    private struct Token: Encodable {
        let token: String
    }

    private struct AuthReply: Decodable {
        let rpceAuth: Status

        enum CodingKeys: String, CodingKey {
            case rpceAuth = "rpce_auth"
        }
    }

    private struct Status: Decodable {
        let status: String
    }

    private static func writeAuthRequest(token: String, to fd: Int32) throws {
        var data = try JSONEncoder().encode(AuthRequest(rpceAuth: Token(token: token)))
        data.append(0x0A)
        try writeAll(data, to: fd)
    }

    private static func readAuthResponse(from fd: Int32) async throws -> AuthResponse {
        guard let line = try await readAuthResponseLine(from: fd),
              let reply = try? JSONDecoder().decode(AuthReply.self, from: line)
        else {
            return .rejected
        }

        return reply.rpceAuth.status == "accepted" ? .accepted : .rejected
    }

    private static func readAuthResponseLine(from fd: Int32) async throws -> Data? {
        let maxBytes = 4096
        let timeout = Date().addingTimeInterval(10)
        let originalFlags = fcntl(fd, F_GETFL)
        guard originalFlags >= 0 else { throw POSIXFailure(operation: "fcntl(F_GETFL)", code: errno) }
        guard fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            throw POSIXFailure(operation: "fcntl(F_SETFL)", code: errno)
        }
        defer { _ = fcntl(fd, F_SETFL, originalFlags) }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(128)

        while Date() < timeout {
            var byte: UInt8 = 0
            let readCount = withUnsafeMutablePointer(to: &byte) { pointer in
                read(fd, pointer, 1)
            }
            if readCount == 1 {
                if byte == 0x0A {
                    return Data(bytes)
                }
                guard bytes.count < maxBytes else { return nil }
                bytes.append(byte)
                continue
            }
            if readCount == 0 { return nil }

            let code = errno
            if code == EINTR { continue }
            if code == EAGAIN || code == EWOULDBLOCK {
                try await Task.sleep(for: .milliseconds(10))
                continue
            }
            throw POSIXFailure(operation: "read", code: code)
        }

        return nil
    }

    private static func pump(inputFD: Int32, outputFD: Int32) throws {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let readCount = buffer.withUnsafeMutableBufferPointer { pointer in
                read(inputFD, pointer.baseAddress, pointer.count)
            }
            if readCount == 0 { return }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw POSIXFailure(operation: "read", code: errno)
            }
            try writeAll(Data(buffer[0 ..< readCount]), to: outputFD)
        }
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = write(fd, base.advanced(by: offset), rawBuffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXFailure(operation: "write", code: errno)
                }
                offset += written
            }
        }
    }
}
