import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

final class HeadlessUnixSocketListener {
    let path: String
    private var listenFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?

    init(path: String) {
        self.path = path
    }

    func start(onAccept: @escaping @Sendable (Int32) async -> Void) throws {
        guard listenFD < 0 else { return }
        guard path.utf8.count < MemoryLayout<sockaddr_un>.size - 2 else {
            throw HeadlessToolFailure(message: "socket path is too long: \(path)")
        }

        let fd = socket(AF_UNIX, streamSocketType, 0)
        guard fd >= 0 else { throw POSIXFailure(operation: "socket", code: errno) }
        listenFD = fd

        try setCloseOnExec(fd)
        _ = unlink(path)

        var address = try makeUnixSocketAddress(path: path)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            closeFD(fd)
            listenFD = -1
            throw POSIXFailure(operation: "bind", code: code)
        }
        chmod(path, S_IRUSR | S_IWUSR)
        guard listen(fd, 16) == 0 else {
            let code = errno
            closeFD(fd)
            unlink(path)
            listenFD = -1
            throw POSIXFailure(operation: "listen", code: code)
        }

        acceptTask = Task.detached {
            while !Task.isCancelled {
                let client = accept(fd, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                Task.detached {
                    await onAccept(client)
                }
            }
        }
    }

    func stop() {
        acceptTask?.cancel()
        acceptTask = nil
        if listenFD >= 0 {
            closeFD(listenFD)
            listenFD = -1
        }
        unlink(path)
    }

    deinit {
        stop()
    }
}

struct POSIXFailure: Error, LocalizedError {
    let operation: String
    let code: Int32

    var errorDescription: String? {
        "\(operation) failed: \(String(cString: strerror(code)))"
    }
}

func defaultHeadlessSocketPath() -> String {
    "/tmp/rpce-headless-\(getpid()).sock"
}

func makeUnixSocketAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    try withUnsafeMutableBytes(of: &address.sun_path) { bytes in
        try path.withCString { cString in
            let length = strlen(cString)
            guard length < bytes.count else {
                throw HeadlessToolFailure(message: "socket path is too long: \(path)")
            }
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            bytes.copyBytes(from: UnsafeRawBufferPointer(start: cString, count: length))
        }
    }
    return address
}

private func setCloseOnExec(_ fd: Int32) throws {
    let flags = fcntl(fd, F_GETFD)
    guard flags >= 0 else { throw POSIXFailure(operation: "fcntl(F_GETFD)", code: errno) }
    guard fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0 else {
        throw POSIXFailure(operation: "fcntl(F_SETFD)", code: errno)
    }
}

func closeFD(_ fd: Int32) {
    #if canImport(Darwin)
        Darwin.close(fd)
    #elseif canImport(Glibc)
        Glibc.close(fd)
    #endif
}

var streamSocketType: Int32 {
    #if canImport(Darwin)
        Int32(SOCK_STREAM)
    #else
        Int32(SOCK_STREAM.rawValue)
    #endif
}

var shutdownWriteValue: Int32 {
    #if canImport(Darwin)
        Int32(SHUT_WR)
    #else
        Int32(SHUT_WR)
    #endif
}
