import Foundation

public protocol FileSystemItem: Identifiable, Equatable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var path: String { get }
    var modificationDate: Date { get }
}

public struct Folder: FileSystemItem {
    public let id: UUID
    public let name: String
    public let path: String
    public let modificationDate: Date

    public init(id: UUID = UUID(), name: String, path: String, modificationDate: Date) {
        self.id = id
        self.name = name
        self.path = path
        self.modificationDate = modificationDate
    }

    public static func == (lhs: Folder, rhs: Folder) -> Bool {
        lhs.path == rhs.path
    }
}

extension FileSystemItem {
    public func relativePath(rootPath: String) -> String {
        RelativePath.from(absolutePath: path, rootPath: rootPath)
    }
}

public struct File: FileSystemItem {
    public let id: UUID
    public let name: String
    public let path: String
    public let modificationDate: Date

    public init(id: UUID = UUID(), name: String, path: String, modificationDate: Date) {
        self.id = id
        self.name = name
        self.path = path
        self.modificationDate = modificationDate
    }

    public static func == (lhs: File, rhs: File) -> Bool {
        lhs.path == rhs.path
    }
}
