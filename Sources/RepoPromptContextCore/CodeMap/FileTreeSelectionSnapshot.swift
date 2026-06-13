import Foundation

public struct FileTreeSelectionSnapshot {
    public let roots: [FileTreeFolderSnapshot]
    public let selectedFileIDs: Set<UUID>
    public let mode: String
    public let showFullPaths: Bool
    public let onlyIncludeRootsWithSelectedFiles: Bool
    public let includeLegend: Bool
    public let showCodeMapMarkers: Bool
    public let maxDepth: Int?

    public init(
        roots: [FileTreeFolderSnapshot],
        selectedFileIDs: Set<UUID>,
        mode: String,
        showFullPaths: Bool,
        onlyIncludeRootsWithSelectedFiles: Bool,
        includeLegend: Bool,
        showCodeMapMarkers: Bool = true,
        maxDepth: Int? = nil
    ) {
        self.roots = roots
        self.selectedFileIDs = selectedFileIDs
        self.mode = mode
        self.showFullPaths = showFullPaths
        self.onlyIncludeRootsWithSelectedFiles = onlyIncludeRootsWithSelectedFiles
        self.includeLegend = includeLegend
        self.showCodeMapMarkers = showCodeMapMarkers
        self.maxDepth = maxDepth
    }
}

public struct FileTreeFolderSnapshot: Hashable {
    public let id: UUID
    public let name: String
    public let fullPath: String
    public let standardizedFullPath: String
    public let standardizedRootPath: String
    public let children: [FileTreeNodeSnapshot]

    public init(id: UUID, name: String, fullPath: String, standardizedFullPath: String, standardizedRootPath: String, children: [FileTreeNodeSnapshot]) {
        self.id = id
        self.name = name
        self.fullPath = fullPath
        self.standardizedFullPath = standardizedFullPath
        self.standardizedRootPath = standardizedRootPath
        self.children = children
    }
}

public struct FileTreeFileSnapshot: Hashable {
    public let id: UUID
    public let name: String
    public let fileExtension: String?
    public let hasCodeMap: Bool

    public init(id: UUID, name: String, fileExtension: String?, hasCodeMap: Bool) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.hasCodeMap = hasCodeMap
    }
}

public indirect enum FileTreeNodeSnapshot: Hashable {
    case folder(FileTreeFolderSnapshot)
    case file(FileTreeFileSnapshot)

    public var id: UUID {
        switch self {
        case let .folder(folder): folder.id
        case let .file(file): file.id
        }
    }

    public var name: String {
        switch self {
        case let .folder(folder): folder.name
        case let .file(file): file.name
        }
    }
}
