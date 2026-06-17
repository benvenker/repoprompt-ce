import Foundation

#if canImport(Darwin)
    import Darwin

    private typealias HeadlessSpawnFileActions = posix_spawn_file_actions_t?
    private typealias HeadlessSpawnAttributes = posix_spawnattr_t?
#elseif canImport(Glibc)
    import Glibc

    private typealias HeadlessSpawnFileActions = posix_spawn_file_actions_t
    private typealias HeadlessSpawnAttributes = posix_spawnattr_t
#endif

enum HeadlessProcessGroupLauncher {
    struct SpawnedProcess {
        let pid: pid_t
    }

    static func spawn(
        argv: [String],
        environment: [String: String],
        stdoutWriteFD: Int32,
        stderrWriteFD: Int32
    ) throws -> SpawnedProcess {
        guard let command = argv.first, !command.isEmpty else {
            throw HeadlessToolFailure(message: "failed to spawn process: argv must contain a command")
        }

        var fileActions = emptyFileActions()
        let fileActionsInitResult = posix_spawn_file_actions_init(&fileActions)
        guard fileActionsInitResult == 0 else {
            throw spawnSetupFailure(command: command, operation: "posix_spawn_file_actions_init", code: fileActionsInitResult)
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        try checkFileAction(
            command: command,
            operation: "open(/dev/null)",
            result: "/dev/null".withCString { path in
                posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, path, O_RDONLY, 0)
            }
        )
        try checkFileAction(
            command: command,
            operation: "dup2(stdout)",
            result: posix_spawn_file_actions_adddup2(&fileActions, stdoutWriteFD, STDOUT_FILENO)
        )
        try checkFileAction(
            command: command,
            operation: "dup2(stderr)",
            result: posix_spawn_file_actions_adddup2(&fileActions, stderrWriteFD, STDERR_FILENO)
        )
        try checkFileAction(
            command: command,
            operation: "close(stdout write)",
            result: posix_spawn_file_actions_addclose(&fileActions, stdoutWriteFD)
        )
        if stderrWriteFD != stdoutWriteFD {
            try checkFileAction(
                command: command,
                operation: "close(stderr write)",
                result: posix_spawn_file_actions_addclose(&fileActions, stderrWriteFD)
            )
        }

        var attributes = emptyAttributes()
        let attributesInitResult = posix_spawnattr_init(&attributes)
        guard attributesInitResult == 0 else {
            throw spawnSetupFailure(command: command, operation: "posix_spawnattr_init", code: attributesInitResult)
        }
        defer { posix_spawnattr_destroy(&attributes) }

        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        sigaddset(&defaultSignals, SIGPIPE)
        var signalMask = sigset_t()
        sigemptyset(&signalMask)

        try checkSpawnAttribute(
            command: command,
            operation: "setsigdefault",
            result: posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        )
        try checkSpawnAttribute(
            command: command,
            operation: "setsigmask",
            result: posix_spawnattr_setsigmask(&attributes, &signalMask)
        )
        try checkSpawnAttribute(
            command: command,
            operation: "setpgroup",
            result: posix_spawnattr_setpgroup(&attributes, 0)
        )

        var flags: Int16 = 0
        try checkSpawnAttribute(
            command: command,
            operation: "getflags",
            result: posix_spawnattr_getflags(&attributes, &flags)
        )
        var configuredFlags = flags | Int16(POSIX_SPAWN_SETPGROUP) | Int16(POSIX_SPAWN_SETSIGDEF) | Int16(POSIX_SPAWN_SETSIGMASK)
        #if canImport(Darwin)
            configuredFlags |= Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
        #endif
        try checkSpawnAttribute(
            command: command,
            operation: "setflags",
            result: posix_spawnattr_setflags(&attributes, configuredFlags)
        )

        let cArgv = try makeCStringArray(argv, failureMessage: "failed to allocate argv for '\(command)'")
        defer { freeCStringArray(cArgv) }

        let envpSource = environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        let cEnvp = try makeCStringArray(envpSource, failureMessage: "failed to allocate environment for '\(command)'")
        defer { freeCStringArray(cEnvp) }

        var mutableArgv = cArgv
        var mutableEnvp = cEnvp
        var pid: pid_t = 0
        let spawnResult = command.withCString { commandPointer in
            posix_spawnp(
                &pid,
                commandPointer,
                &fileActions,
                &attributes,
                &mutableArgv,
                &mutableEnvp
            )
        }
        guard spawnResult == 0 else {
            throw HeadlessToolFailure(message: "failed to spawn '\(command)': errno \(spawnResult) (\(systemMessage(for: spawnResult)))")
        }

        return SpawnedProcess(pid: pid)
    }

    static func reapExitCode(pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while true {
            let result = waitpid(pid, &status, 0)
            if result == pid {
                return normalizedExitCode(status)
            }
            if result == -1, errno == EINTR {
                continue
            }
            if result == -1 {
                return 1
            }
        }
    }

    private static func checkFileAction(command: String, operation: String, result: Int32) throws {
        guard result == 0 else {
            throw spawnSetupFailure(command: command, operation: operation, code: result)
        }
    }

    private static func checkSpawnAttribute(command: String, operation: String, result: Int32) throws {
        guard result == 0 else {
            throw spawnSetupFailure(command: command, operation: operation, code: result)
        }
    }

    private static func spawnSetupFailure(command: String, operation: String, code: Int32) -> HeadlessToolFailure {
        HeadlessToolFailure(message: "failed to configure spawn for '\(command)' during \(operation): errno \(code) (\(systemMessage(for: code)))")
    }

    private static func makeCStringArray(_ values: [String], failureMessage: String) throws -> [UnsafeMutablePointer<CChar>?] {
        var pointers: [UnsafeMutablePointer<CChar>?] = []
        pointers.reserveCapacity(values.count + 1)
        for value in values {
            guard let pointer = strdup(value) else {
                freeCStringArray(pointers)
                throw HeadlessToolFailure(message: failureMessage)
            }
            pointers.append(pointer)
        }
        pointers.append(nil)
        return pointers
    }

    private static func freeCStringArray(_ pointers: [UnsafeMutablePointer<CChar>?]) {
        for pointer in pointers where pointer != nil {
            free(pointer)
        }
    }

    private static func normalizedExitCode(_ status: Int32) -> Int32 {
        (status & 0x7F) == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
    }

    private static func systemMessage(for code: Int32) -> String {
        String(cString: strerror(code))
    }

    private static func emptyFileActions() -> HeadlessSpawnFileActions {
        #if canImport(Darwin)
            nil
        #elseif canImport(Glibc)
            posix_spawn_file_actions_t()
        #endif
    }

    private static func emptyAttributes() -> HeadlessSpawnAttributes {
        #if canImport(Darwin)
            nil
        #elseif canImport(Glibc)
            posix_spawnattr_t()
        #endif
    }
}
