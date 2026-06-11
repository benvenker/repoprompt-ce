import Foundation
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    import Darwin
#else
    import Glibc
#endif

public struct FileContentFingerprint: Hashable {
    public let deviceID: UInt64
    public let fileNumber: UInt64
    public let byteSize: Int64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64
    public let statusChangeSeconds: Int64
    public let statusChangeNanoseconds: Int64

    public var modificationDate: Date {
        Date(
            timeIntervalSince1970: TimeInterval(modificationSeconds)
                + TimeInterval(modificationNanoseconds) / 1_000_000_000
        )
    }
}

public struct ValidatedFileContentSnapshot {
    public let content: String?
    public let detectedEncodingRawValue: UInt?
    public let modificationDate: Date
    public let fingerprint: FileContentFingerprint

    public var estimatedDecodedCost: Int {
        guard let content else { return 0 }
        return content.utf8.count + content.utf16.count * MemoryLayout<UInt16>.stride
    }
}

public enum FileContentValidationError: Error {
    case fingerprintChanged
}

public enum FileContentFingerprintReader {
    public static func fingerprint(atPath path: String) throws -> FileContentFingerprint {
        var info = stat()
        let result = path.withCString { pointer in
            lstat(pointer, &info)
        }
        guard result == 0 else {
            throw fileSystemError(for: errno)
        }
        return try fingerprint(from: info)
    }

    public static func fingerprint(fileDescriptor: Int32) throws -> FileContentFingerprint {
        var info = stat()
        guard fstat(fileDescriptor, &info) == 0 else {
            throw fileSystemError(for: errno)
        }
        return try fingerprint(from: info)
    }

    public static func openReadOnlyFileHandle(atPath path: String) throws -> FileHandle {
        let descriptor = path.withCString { pointer in
            open(pointer, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw fileSystemError(for: errno)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func fingerprint(from info: stat) throws -> FileContentFingerprint {
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw FileSystemError.invalidRelativePath
        }

        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let modificationTime = info.st_mtimespec
            let statusChangeTime = info.st_ctimespec
        #else
            let modificationTime = info.st_mtim
            let statusChangeTime = info.st_ctim
        #endif

        return FileContentFingerprint(
            deviceID: UInt64(info.st_dev),
            fileNumber: UInt64(info.st_ino),
            byteSize: Int64(info.st_size),
            modificationSeconds: Int64(modificationTime.tv_sec),
            modificationNanoseconds: Int64(modificationTime.tv_nsec),
            statusChangeSeconds: Int64(statusChangeTime.tv_sec),
            statusChangeNanoseconds: Int64(statusChangeTime.tv_nsec)
        )
    }

    private static func fileSystemError(for errorNumber: Int32) -> FileSystemError {
        switch errorNumber {
        case ENOENT, ENOTDIR:
            .fileNotFound
        case ELOOP:
            .invalidRelativePath
        default:
            .failedToReadFile
        }
    }
}
