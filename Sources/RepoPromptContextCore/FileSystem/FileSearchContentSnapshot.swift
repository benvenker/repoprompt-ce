import Foundation

public enum FileContentFreshnessPolicy {
    /// Trust the existing FileViewModel metadata/cache fast path.
    case cachedMetadata
    /// Validate disk metadata before trusting cached content; never return stale fallback on validation/load failure.
    case validateDiskMetadata
}

/// Snapshot of file content plus a stable in-memory revision for search cache identity.
public struct FileSearchContentSnapshot {
    public let content: String?
    public let contentRevision: UInt64?
    public let modificationDate: Date
    public let isFresh: Bool

    public init(content: String?, contentRevision: UInt64?, modificationDate: Date, isFresh: Bool) {
        self.content = content
        self.contentRevision = contentRevision
        self.modificationDate = modificationDate
        self.isFresh = isFresh
    }
}
