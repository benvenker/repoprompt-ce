import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

enum ConnectBridge {
    static func run(socketPath: String) async throws {
        let socketFD = try connectSocket(path: socketPath)
        defer { closeFD(socketFD) }

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
