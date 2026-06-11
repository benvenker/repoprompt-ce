import Foundation

public enum FileSystemError: Error {
    case fileAlreadyExists
    case fileNotFound
    case failedToCreateFile(Error)
    case failedToEditFile(Error)
    case failedToDeleteFile(Error)
    case failedToReadFile
    case failedToEnumerateDirectory
    case fileTooLarge
    case isDirectory
    case failedToCreateDirectory(Error)
    case invalidRelativePath
}

extension FileSystemError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            "Unsafe workspace mutation path: target escapes the loaded root, contains traversal, or uses a symbolic-link component."
        default:
            nil
        }
    }
}
