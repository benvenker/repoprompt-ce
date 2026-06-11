import Foundation

public enum CatalogRegularFileIneligibilityReason: Sendable, Equatable, CustomStringConvertible {
    case invalidRelativePath
    case outsideRoot
    case missingOrDirectory
    case symbolicLink
    case nonRegularFile
    case symlinkComponent
    case outsideCanonicalRoot
    case ignored

    public var description: String {
        switch self {
        case .invalidRelativePath:
            "invalid relative path"
        case .outsideRoot:
            "path is outside the workspace root"
        case .missingOrDirectory:
            "path is missing or is a directory"
        case .symbolicLink:
            "path is a symbolic link"
        case .nonRegularFile:
            "path is not a regular file"
        case .symlinkComponent:
            "path contains a symbolic-link component"
        case .outsideCanonicalRoot:
            "canonical path is outside the workspace root"
        case .ignored:
            "path is ignored by workspace policy"
        }
    }
}

public enum CatalogRegularFileEligibility: Sendable, Equatable {
    case eligible
    case ineligible(CatalogRegularFileIneligibilityReason)

    public var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }
}
