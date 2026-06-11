import Foundation

/// Determines how CodeMap definitions are inserted.
public enum CodeMapUsage: String, CaseIterable, Codable {
    case auto
    case complete
    /// Include code-map for selected files only (handled at injection sites; returning it here would duplicate).
    case selected
    case none
}

/// How to include git diff in the copy/prompt context.
public enum GitInclusion: String, Codable, CaseIterable {
    case none
    case selected
    case complete
}

/// A resolved, runtime config after merging preset + workspace overrides + capability checks.
/// Used by both copy and chat prompt builders.
public struct PromptContextResolved {
    public var includeFiles: Bool
    public var includeUserPrompt: Bool
    public var includeMetaPrompts: Bool
    public var includeFileTree: Bool

    public var fileTreeMode: FileTreeOption
    public var codeMapUsage: CodeMapUsage
    public var gitInclusion: GitInclusion

    public var storedPromptIds: [UUID]?

    public var rendersFileTree: Bool {
        includeFileTree && fileTreeMode != .none
    }

    public var effectiveFileTreeMode: FileTreeOption {
        rendersFileTree ? fileTreeMode : .none
    }

    public init(
        includeFiles: Bool,
        includeUserPrompt: Bool,
        includeMetaPrompts: Bool,
        includeFileTree: Bool,
        fileTreeMode: FileTreeOption,
        codeMapUsage: CodeMapUsage,
        gitInclusion: GitInclusion,
        storedPromptIds: [UUID]?
    ) {
        self.includeFiles = includeFiles
        self.includeUserPrompt = includeUserPrompt
        self.includeMetaPrompts = includeMetaPrompts
        self.includeFileTree = includeFileTree
        self.fileTreeMode = fileTreeMode
        self.codeMapUsage = codeMapUsage
        self.gitInclusion = gitInclusion
        self.storedPromptIds = storedPromptIds
    }
}
