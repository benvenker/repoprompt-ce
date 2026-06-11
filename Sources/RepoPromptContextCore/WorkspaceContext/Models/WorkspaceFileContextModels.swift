import Foundation

/// Root scopes shared by UI and headless workspace file lookup paths.
public enum WorkspaceLookupRootScope: Hashable {
    case visibleWorkspace
    case visibleWorkspacePlusGitData
    case allLoaded
    case sessionBoundWorkspace(logicalRootPaths: Set<String>, physicalRootPaths: Set<String>)
}

public enum WorkspaceLookupRootScopeAvailability: Equatable {
    case available
    case sessionWorktreeUnavailable(missingPhysicalRootPaths: [String])
}

public enum WorkspaceSearchCatalogAccess: Equatable {
    case available(WorkspaceSearchCatalogSnapshot)
    case unavailable(WorkspaceLookupRootScopeAvailability)
}

public typealias LookupRootScope = WorkspaceLookupRootScope

public enum WorkspaceRootKind: Hashable {
    case primaryWorkspace
    case workspaceGitData
    case supplementalSystem
    case sessionWorktree
}

public enum WorkspaceExactPathLookupKind: Hashable {
    case file
    case folder
    case either
}

public struct WorkspaceFolderExpansionResult: Equatable {
    public let files: [WorkspaceFileRecord]
    public let handled: Bool
    public let displayPath: String?
    public let issue: PathResolutionIssue?
}

public struct WorkspaceRootLoadFailure: Equatable, Identifiable {
    public let id: UUID
    public let rootPath: String
    public let standardizedRootPath: String
    public let kind: WorkspaceRootKind
    public let errorDescription: String

    public init(id: UUID = UUID(), rootPath: String, kind: WorkspaceRootKind, errorDescription: String) {
        self.id = id
        self.rootPath = rootPath
        standardizedRootPath = StandardizedPath.absolute(rootPath)
        self.kind = kind
        self.errorDescription = errorDescription
    }

    public static func == (lhs: WorkspaceRootLoadFailure, rhs: WorkspaceRootLoadFailure) -> Bool {
        lhs.standardizedRootPath == rhs.standardizedRootPath &&
            lhs.kind == rhs.kind &&
            lhs.errorDescription == rhs.errorDescription
    }
}

public enum WorkspaceSearchReadinessState: Equatable {
    case idle
    case activating(workspaceID: UUID?, generation: UInt64)
    case loadingCatalog(workspaceID: UUID?, generation: UInt64, loadedRootCount: Int, expectedRootCount: Int, failures: [WorkspaceRootLoadFailure])
    case buildingIndexes(workspaceID: UUID?, generation: UInt64, catalogGeneration: UInt64, failures: [WorkspaceRootLoadFailure])
    case ready(workspaceID: UUID?, generation: UInt64, catalogGeneration: UInt64, indexedGeneration: UInt64, diagnostics: WorkspaceCatalogDiagnostics)
    case degraded(workspaceID: UUID?, generation: UInt64, catalogGeneration: UInt64?, indexedGeneration: UInt64?, failures: [WorkspaceRootLoadFailure], diagnostics: WorkspaceCatalogDiagnostics?)
}

public struct WorkspaceCatalogDiagnostics: Equatable {
    public let generation: UInt64
    public let rootScope: WorkspaceLookupRootScope
    public let rootCount: Int
    public let folderCount: Int
    public let fileCount: Int
    public let totalItemCount: Int

    public init(
        generation: UInt64,
        rootScope: WorkspaceLookupRootScope,
        rootCount: Int,
        folderCount: Int,
        fileCount: Int
    ) {
        self.generation = generation
        self.rootScope = rootScope
        self.rootCount = rootCount
        self.folderCount = folderCount
        self.fileCount = fileCount
        totalItemCount = folderCount + fileCount
    }
}

public struct WorkspaceSearchCatalogEntry: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let rootID: UUID
    public let rootPath: String
    public let rootName: String
    public let name: String
    public let relativePath: String
    public let standardizedRelativePath: String
    public let fullPath: String
    public let standardizedFullPath: String
    public let displayPath: String

    public init(file: WorkspaceFileRecord, root: WorkspaceRootRecord, displayPath: String? = nil) {
        id = file.id
        rootID = file.rootID
        rootPath = root.standardizedFullPath
        rootName = root.name
        name = file.name
        relativePath = file.relativePath
        standardizedRelativePath = file.standardizedRelativePath
        fullPath = file.fullPath
        standardizedFullPath = file.standardizedFullPath
        self.displayPath = displayPath ?? WorkspaceSearchCatalogEntry.defaultDisplayPath(file: file, root: root)
    }

    private static func defaultDisplayPath(file: WorkspaceFileRecord, root: WorkspaceRootRecord) -> String {
        guard !file.standardizedRelativePath.isEmpty else { return root.name }
        return root.name + "/" + file.standardizedRelativePath
    }
}

public struct WorkspaceSearchCatalogSnapshot: Equatable {
    public let generation: UInt64
    public let rootScope: WorkspaceLookupRootScope
    public let roots: [WorkspaceRootRecord]
    public let files: [WorkspaceFileRecord]
    public let entries: [WorkspaceSearchCatalogEntry]
    public let diagnostics: WorkspaceCatalogDiagnostics
}

public struct WorkspaceDirectFolderChildrenSnapshot: Equatable {
    public let generation: UInt64
    public let root: WorkspaceRootRecord
    public let folder: WorkspaceFolderRecord
    public let childFolders: [WorkspaceFolderRecord]
    public let childFiles: [WorkspaceFileRecord]

    public var isEmpty: Bool {
        childFolders.isEmpty && childFiles.isEmpty
    }
}

public struct WorkspaceSearchQueryResult: Equatable {
    public let query: String
    public let indexedGeneration: UInt64?
    public let snapshotGeneration: UInt64?
    public let pendingGeneration: UInt64?
    public let observedGeneration: UInt64?
    public let results: [WorkspaceSearchCatalogEntry]
    public let isIndexReady: Bool
    public let isStale: Bool

    public init(
        query: String,
        indexedGeneration: UInt64?,
        snapshotGeneration: UInt64?,
        pendingGeneration: UInt64? = nil,
        observedGeneration: UInt64? = nil,
        results: [WorkspaceSearchCatalogEntry],
        isIndexReady: Bool,
        isStale: Bool = false
    ) {
        self.query = query
        self.indexedGeneration = indexedGeneration
        self.snapshotGeneration = snapshotGeneration
        self.pendingGeneration = pendingGeneration
        self.observedGeneration = observedGeneration
        self.results = results
        self.isIndexReady = isIndexReady
        self.isStale = isStale
    }
}

public struct WorkspaceResolvedCandidates: Equatable {
    public let candidates: [WorkspaceFileRecord]
    public let resolvedMap: [String: String]
    public let invalidPaths: [String]
}

public struct WorkspaceCodemapOnlyCandidates: Equatable {
    public let candidates: [WorkspaceFileRecord]
    public let resolvedMap: [String: String]
    public let invalidPaths: [String]
    public let codemapUnavailable: [String]
}

public struct WorkspaceRootRecord: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let name: String
    public let fullPath: String
    public let standardizedFullPath: String
    public let isSystemRoot: Bool
    public let kind: WorkspaceRootKind

    public init(id: UUID = UUID(), name: String, fullPath: String, isSystemRoot: Bool = false) {
        self.init(
            id: id,
            name: name,
            fullPath: fullPath,
            kind: isSystemRoot ? .supplementalSystem : .primaryWorkspace,
            isSystemRoot: isSystemRoot
        )
    }

    public init(id: UUID = UUID(), name: String, fullPath: String, kind: WorkspaceRootKind) {
        self.init(
            id: id,
            name: name,
            fullPath: fullPath,
            kind: kind,
            isSystemRoot: kind != .primaryWorkspace
        )
    }

    private init(id: UUID, name: String, fullPath: String, kind: WorkspaceRootKind, isSystemRoot: Bool) {
        self.id = id
        self.name = name
        self.fullPath = fullPath
        standardizedFullPath = (fullPath as NSString).standardizingPath
        self.isSystemRoot = isSystemRoot
        self.kind = kind
    }
}

public struct WorkspaceFolderRecord: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let rootID: UUID
    public let name: String
    public let relativePath: String
    public let standardizedRelativePath: String
    public let fullPath: String
    public let standardizedFullPath: String
    public let parentFolderID: UUID?
    public let modificationDate: Date?

    public init(
        id: UUID = UUID(),
        rootID: UUID,
        name: String,
        relativePath: String,
        fullPath: String,
        parentFolderID: UUID?,
        modificationDate: Date? = nil
    ) {
        self.id = id
        self.rootID = rootID
        self.name = name
        self.relativePath = relativePath
        standardizedRelativePath = StandardizedPath.relative(relativePath)
        self.fullPath = fullPath
        standardizedFullPath = (fullPath as NSString).standardizingPath
        self.parentFolderID = parentFolderID
        self.modificationDate = modificationDate
    }
}

public struct WorkspaceFileRecord: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let rootID: UUID
    public let name: String
    public let relativePath: String
    public let standardizedRelativePath: String
    public let fullPath: String
    public let standardizedFullPath: String
    public let parentFolderID: UUID?
    public let modificationDate: Date?

    public init(
        id: UUID = UUID(),
        rootID: UUID,
        name: String,
        relativePath: String,
        fullPath: String,
        parentFolderID: UUID?,
        modificationDate: Date? = nil
    ) {
        self.id = id
        self.rootID = rootID
        self.name = name
        self.relativePath = relativePath
        standardizedRelativePath = StandardizedPath.relative(relativePath)
        self.fullPath = fullPath
        standardizedFullPath = (fullPath as NSString).standardizingPath
        self.parentFolderID = parentFolderID
        self.modificationDate = modificationDate
    }
}

public struct ResolvedWorkspaceSelection: Equatable {
    public let files: [WorkspaceFileRecord]
    public let folders: [WorkspaceFolderRecord]
    public let missingPaths: [String]
}

public struct ResolvedPromptFileEntry: Identifiable, Equatable {
    public let id: ResolvedPromptFileEntryID
    public let file: WorkspaceFileRecord
    public let isCodemap: Bool
    public let lineRanges: [LineRange]?
    public let mode: PromptFileEntryMode
    public let loadedContent: String?
    public let rootFolderPath: String?

    public init(
        file: WorkspaceFileRecord,
        isCodemap: Bool = false,
        lineRanges: [LineRange]? = nil,
        mode: PromptFileEntryMode = .fullFile,
        loadedContent: String? = nil,
        rootFolderPath: String? = nil
    ) {
        id = ResolvedPromptFileEntryID(fileID: file.id, mode: mode, lineRanges: lineRanges)
        self.file = file
        self.isCodemap = isCodemap
        self.lineRanges = lineRanges
        self.mode = mode
        self.loadedContent = loadedContent
        self.rootFolderPath = rootFolderPath
    }
}

public struct ResolvedPromptFileBlockRecord: Equatable {
    public let entry: ResolvedPromptFileEntry
    public let file: WorkspaceFileRecord
    public let text: String
    public let isCodemap: Bool

    public init(entry: ResolvedPromptFileEntry, file: WorkspaceFileRecord, text: String, isCodemap: Bool) {
        self.entry = entry
        self.file = file
        self.text = text
        self.isCodemap = isCodemap
    }
}

public struct ResolvedPromptFileEntryID: Hashable {
    public let fileID: UUID
    public let mode: PromptFileEntryMode
    public let lineRanges: [LineRange]?
}

public enum PromptFileEntryMode: Hashable {
    case fullFile
    case sliced
    case codemap
}

public struct WorkspaceExternalReadableFile: Equatable, Hashable {
    public let absolutePath: String
    public let displayPath: String
}

public enum WorkspaceReadableFileHandle: Equatable {
    case workspace(WorkspaceFileRecord)
    case external(WorkspaceExternalReadableFile)
}

public struct WorkspaceFileSystemDeltaEvent: Equatable {
    public let rootID: UUID
    public let rootPath: String
    public let delta: FileSystemDelta
}

public struct WorkspaceIngressBarrierSample: Equatable {
    public let rootID: UUID
    public let rootPath: String
    public let pendingRawEventCountBeforeFlush: Int
    public let acceptedWatcherWatermark: UInt64
    public let publishedServicePublicationSequence: UInt64
    public let appliedServicePublicationSequence: UInt64
    public let appliedWatcherWatermark: UInt64
}

public struct WorkspaceAppliedIndexBatchEvent: Equatable {
    public let rootID: UUID
    public let rootPath: String
    public let generation: UInt64
    public let upsertedFiles: [WorkspaceFileRecord]
    public let upsertedFolders: [WorkspaceFolderRecord]
    public let removedFileIDs: [UUID]
    public let removedFolderIDs: [UUID]
    public let removedFilePaths: [String]
    public let removedFolderPaths: [String]
    public let modifiedFileIDs: [UUID]
    public let modifiedFolderIDs: [UUID]
    public let requiresFullResync: Bool
    public let isRootUnload: Bool

    public init(
        rootID: UUID,
        rootPath: String,
        generation: UInt64,
        upsertedFiles: [WorkspaceFileRecord] = [],
        upsertedFolders: [WorkspaceFolderRecord] = [],
        removedFileIDs: [UUID] = [],
        removedFolderIDs: [UUID] = [],
        removedFilePaths: [String] = [],
        removedFolderPaths: [String] = [],
        modifiedFileIDs: [UUID] = [],
        modifiedFolderIDs: [UUID] = [],
        requiresFullResync: Bool = false,
        isRootUnload: Bool = false
    ) {
        self.rootID = rootID
        self.rootPath = rootPath
        self.generation = generation
        self.upsertedFiles = upsertedFiles
        self.upsertedFolders = upsertedFolders
        self.removedFileIDs = removedFileIDs
        self.removedFolderIDs = removedFolderIDs
        self.removedFilePaths = removedFilePaths
        self.removedFolderPaths = removedFolderPaths
        self.modifiedFileIDs = modifiedFileIDs
        self.modifiedFolderIDs = modifiedFolderIDs
        self.requiresFullResync = requiresFullResync
        self.isRootUnload = isRootUnload
    }
}

public struct WorkspaceCodemapSnapshot {
    public let fileID: UUID
    public let rootID: UUID
    public let rootPath: String
    public let relativePath: String
    public let fullPath: String
    public let modificationDate: Date
    public let fileAPI: FileAPI?
}

public struct WorkspaceCodemapUpdateEvent {
    public let rootID: UUID
    public let rootPath: String
    public let snapshots: [WorkspaceCodemapSnapshot]
    public let removedFileIDs: [UUID]
    public let isRootUnload: Bool

    public init(
        rootID: UUID,
        rootPath: String,
        snapshots: [WorkspaceCodemapSnapshot],
        removedFileIDs: [UUID] = [],
        isRootUnload: Bool = false
    ) {
        self.rootID = rootID
        self.rootPath = rootPath
        self.snapshots = snapshots
        self.removedFileIDs = removedFileIDs
        self.isRootUnload = isRootUnload
    }
}

public struct WorkspacePathLookupRequest: Equatable {
    public let userPath: String
    public let profile: PathLocateProfile
    public let rootScope: WorkspaceLookupRootScope
    public let selectedFileFullPaths: Set<String>

    public init(
        userPath: String,
        profile: PathLocateProfile = .uiAssisted,
        rootScope: WorkspaceLookupRootScope = .allLoaded,
        selectedFileFullPaths: Set<String> = []
    ) {
        self.userPath = userPath
        self.profile = profile
        self.rootScope = rootScope
        self.selectedFileFullPaths = selectedFileFullPaths
    }
}

public struct WorkspacePathLocation: Equatable, Hashable {
    public let rootID: UUID
    public let rootPath: String
    public let correctedPath: String

    public var absolutePath: String {
        let standardizedRoot = (rootPath as NSString).standardizingPath
        if correctedPath.hasPrefix("/") {
            return (correctedPath as NSString).standardizingPath
        }
        return ((standardizedRoot as NSString).appendingPathComponent(correctedPath) as NSString).standardizingPath
    }
}

public struct WorkspacePathLookupResult: Equatable {
    public let input: String
    public let location: WorkspacePathLocation
    public let file: WorkspaceFileRecord?
    public let folder: WorkspaceFolderRecord?
}
